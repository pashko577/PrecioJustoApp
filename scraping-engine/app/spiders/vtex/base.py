"""Extractor genérico para tiendas VTEX (Coolbox, Plaza Vea, Oechsle, Promart, Wong...).

Usa el catálogo público de VTEX (`/api/catalog_system/pub/products/search`), que devuelve datos
estructurados (JSON). Es más estable que leer el HTML y genera muchas menos solicitudes.

Reglas de extracción responsable (COMPRA_MEJOR.md, 7.7):
- Respeta robots.txt (ROBOTSTXT_OBEY) y se identifica como CompraMejorBot.
- Una solicitud a la vez, con pausa entre solicitudes.
- Ante HTTP 429 (demasiadas solicitudes) o 403 se DETIENE; no reintenta ni evade.
"""

from __future__ import annotations

import json
import os
import re
from datetime import datetime, timedelta, timezone
from urllib.parse import urlencode

import scrapy
from scrapy.exceptions import CloseSpider

from app.models.offer import ScrapedOffer
from app.normalizers.identifiers import canonical_gtin, canonical_mpn
from app.normalizers.price import number_to_cents
from app.normalizers.text import normalize_text, word_tokens
from app.pipelines.job_errors import record_error

PAGE_SIZE = 50          # máximo que permite VTEX por solicitud
# Alcance por categoría: los primeros 200 productos (los más relevantes según la tienda). Leer
# catálogos completos (Plaza Vea: 7 200 publicaciones) no cabe en la cuota gratuita de Firestore.
DEFAULT_SCOPE_PAGES = 4
MAX_OFFSET = 2500       # VTEX no permite paginar más allá de este índice
STOP_STATUSES = (403, 429)
# Margen para que una corrida programada no se salte por unos minutos de diferencia del cron.
SCHEDULE_TOLERANCE = timedelta(minutes=45)


def is_due(store: dict | None, now: datetime | None = None) -> bool:
    """¿Toca extraer esta tienda? Según `scrapingIntervalMinutes` y `lastCompleteRunAt`."""
    if not store:
        return True
    last = store.get("lastCompleteRunAt")
    if last is None:
        return True
    now = now or datetime.now(timezone.utc)
    interval = timedelta(minutes=int(store.get("scrapingIntervalMinutes") or 360))
    return now - last >= interval - SCHEDULE_TOLERANCE

_RESOURCES_RE = re.compile(r"(\d+)-(\d+)/(\d+)")
_REFURBISHED_RE = re.compile(r"reacondicionad|refurbished|open box|seminuevo", re.I)


def parse_total(resources_header: str | bytes | None) -> int | None:
    """`resources: 0-49/130` -> 130."""
    if not resources_header:
        return None
    if isinstance(resources_header, bytes):
        resources_header = resources_header.decode("latin-1")
    match = _RESOURCES_RE.search(resources_header)
    return int(match.group(3)) if match else None


def clean_title(product_name: str | None, item_name: str | None, name_complete: str | None = None) -> str:
    """Título sin repeticiones.

    VTEX arma `nameComplete` como `productName + itemName`. Cuando la variante repite el nombre
    del producto con otras palabras, el resultado sale duplicado ("SSD Kingston A400, 480GB ...
    SSD Kingston A400 480GB ..."). Solo se agrega la variante si aporta palabras nuevas.
    """
    product = (product_name or "").strip()
    item = (item_name or "").strip()
    if not product:
        return item or (name_complete or "").strip()
    if not item or normalize_text(item) == normalize_text(product):
        return product
    product_words, item_words = set(word_tokens(product)), set(word_tokens(item))
    if item_words <= product_words:
        return product            # la variante no agrega nada
    if product_words <= item_words:
        return item               # la variante es el nombre más completo
    if len(item) <= 40:
        return f"{product} - {item}"   # p. ej. "Laptop X ... - Azul"
    extra = [w for w in item.split() if word_tokens(w) and set(word_tokens(w)) - product_words]
    return f"{product} - {' '.join(extra)}" if extra else product


# Una palabra con letras y números; sin 10+ dígitos seguidos (códigos internos de vendedores
# con fecha, como "GameCenter-1695497308512").
_MODEL_CODE_RE = re.compile(r"^(?=.*[A-Za-z])(?=.*\d)(?!.*\d{10})[A-Za-z0-9][A-Za-z0-9./_#-]{3,30}$")


def looks_like_model_code(value: str | None) -> bool:
    """¿Parece un código de fabricante: UNA palabra con letras y números, de 5+ caracteres?

    Rechaza correlativos internos solo numéricos ("20329474") y nombres comerciales con espacios
    ("PlayStation 5 Slim", "Switch 2", "Galaxy A16"): esos los comparten variantes y paquetes
    distintos, y usarlos como código uniría productos diferentes.
    """
    return bool(value) and bool(_MODEL_CODE_RE.match(value.strip()))


def pick_mpn(product: dict) -> str | None:
    """Código del fabricante de un producto VTEX.

    - Coolbox: `productReference` es el modelo real ("SA400S37960GB").
    - Plaza Vea, Oechsle, Promart: `productReference` es un correlativo interno ("20329474") y el
      modelo real está en la especificación "Modelo" ("RI-795DI").
    """
    reference = (product.get("productReference") or "").strip()
    if looks_like_model_code(reference):
        return reference
    for key in ("Modelo", "Model", "Código de modelo", "Número de modelo"):
        values = product.get(key)
        value = (values[0] if isinstance(values, list) and values else values) or ""
        if isinstance(value, str) and looks_like_model_code(value.strip()):
            return value.strip()
    return None


def _default_seller(item: dict) -> dict | None:
    sellers = item.get("sellers") or []
    return next((s for s in sellers if s.get("sellerDefault")), sellers[0] if sellers else None)


def seller_name(seller: dict, internal_prefixes: tuple[str, ...] = ()) -> str | None:
    """Nombre del vendedor; `None` si es la propia tienda.

    Algunas tiendas venden con cuentas internas (Metro: "wongiononfood"); esas no son
    vendedores externos y no deben mostrarse como tal.
    """
    seller_id = str(seller.get("sellerId") or "")
    if seller_id == "1" or any(seller_id.startswith(p) for p in internal_prefixes):
        return None
    return (seller.get("sellerName") or "").strip() or None


def offers_from_product(product: dict, *, store_code: str, category_slug: str | None,
                        checked_at: datetime | None = None,
                        internal_sellers: tuple[str, ...] = ()) -> tuple[list[ScrapedOffer], list[str]]:
    """Convierte un producto VTEX en ofertas (una por SKU/variante).

    Devuelve `(ofertas, avisos)`. Los avisos describen SKUs descartados (por ejemplo, sin precio).
    """
    checked_at = checked_at or datetime.now(timezone.utc)
    offers: list[ScrapedOffer] = []
    warnings: list[str] = []
    categories_text = " ".join(product.get("categories") or [])
    mpn = pick_mpn(product)

    for item in product.get("items") or []:
        sku = str(item.get("itemId") or "").strip()
        seller = _default_seller(item)
        if not sku or seller is None:
            warnings.append(f"producto {product.get('productId')}: SKU sin id o sin vendedor")
            continue
        offer_data = seller.get("commertialOffer") or {}
        price_cents = number_to_cents(offer_data.get("Price"))
        if price_cents is None:
            # VTEX publica precio 0 para SKUs sin stock ni precio: no es un precio real.
            warnings.append(f"SKU {sku}: sin precio válido ({offer_data.get('Price')!r})")
            continue

        list_cents = number_to_cents(offer_data.get("ListPrice"))
        quantity = offer_data.get("AvailableQuantity") or 0
        available = bool(offer_data.get("IsAvailable", quantity > 0)) and quantity > 0
        title = clean_title(product.get("productName"), item.get("name"), item.get("nameComplete"))

        identifiers: dict[str, str] = {}
        if gtin := canonical_gtin(item.get("ean")):
            identifiers["GTIN"] = gtin
        if mpn:
            identifiers["MPN"] = canonical_mpn(mpn)

        images = item.get("images") or []
        offers.append(ScrapedOffer(
            store_code=store_code,
            external_product_id=sku,
            title=title,
            brand=(product.get("brand") or "").strip() or None,
            model=mpn,
            price_cents=price_cents,
            list_price_cents=list_cents if list_cents and list_cents > price_cents else None,
            shipping_cents=None,  # el costo de envío depende de la dirección: desconocido
            availability="AVAILABLE" if available else "OUT_OF_STOCK",
            condition="REFURBISHED" if _REFURBISHED_RE.search(f"{title} {categories_text}") else "NEW",
            seller=seller_name(seller, internal_sellers),
            identifiers=identifiers,
            category_hint=category_slug,
            product_url=product.get("link") or "",
            image_url=images[0].get("imageUrl") if images else None,
            checked_at=checked_at,
        ))
    return offers, warnings


class VtexSpider(scrapy.Spider):
    """Base: cada tienda define `store_code`, `base_url` y `categories`."""

    store_code: str = ""
    base_url: str = ""
    # Ruta de categoría VTEX (ids, por ejemplo "/47/65/") -> slug de nuestra categoría.
    categories: dict[str, str] = {}
    internal_sellers: tuple[str, ...] = ()  # prefijos de sellerId que son la propia tienda
    scope_pages: int = DEFAULT_SCOPE_PAGES  # alcance normal (la corrida sigue siendo completa)

    handle_httpstatus_list = list(STOP_STATUSES)
    custom_settings = {
        "DOWNLOAD_DELAY": 5,
        "CONCURRENT_REQUESTS_PER_DOMAIN": 1,
        "RETRY_HTTP_CODES": [500, 502, 503, 504, 522, 524, 408],  # 429 NO se reintenta
        "DEFAULT_REQUEST_HEADERS": {"Accept": "application/json"},
    }

    def __init__(self, *args, max_pages: int | str | None = None, **kwargs):
        super().__init__(*args, **kwargs)
        # Límite opcional de páginas por categoría (útil para pruebas: -a max_pages=1).
        self.max_pages = int(max_pages) if max_pages else None
        self.job_errors: list[dict] = []
        self.stopped_early = False
        self.not_due = False

    def search_url(self, category_path: str, offset: int) -> str:
        query = urlencode({"fq": f"C:{category_path}", "_from": offset, "_to": offset + PAGE_SIZE - 1})
        return f"{self.base_url}/api/catalog_system/pub/products/search?{query}"

    def make_request(self, category_path: str, slug: str, offset: int) -> scrapy.Request:
        return scrapy.Request(
            self.search_url(category_path, offset),
            callback=self.parse_page,
            cb_kwargs={"category_path": category_path, "slug": slug, "offset": offset},
        )

    def _store_is_due(self) -> bool:
        """Las corridas programadas respetan la frecuencia de la tienda; las manuales siempre corren."""
        if os.getenv("JOB_TYPE") != "SCHEDULED":
            return True
        from app.firebase_client import get_db  # import tardío: las pruebas no necesitan Firestore

        snap = get_db().collection("stores").document(self.store_code).get()
        return is_due(snap.to_dict() if snap.exists else None)

    async def start(self):
        if getattr(self, "not_due", False):  # el pipeline decidió no correr (presupuesto diario)
            return
        if not self._store_is_due():
            self.not_due = True
            self.logger.info("%s: todavía no toca según su frecuencia; no se hacen solicitudes.", self.store_code)
            return
        for category_path, slug in self.categories.items():
            yield self.make_request(category_path, slug, 0)

    def parse_page(self, response, category_path: str, slug: str, offset: int):
        if response.status in STOP_STATUSES:
            self.stopped_early = True
            message = f"HTTP {response.status} en {category_path}: la tienda pidió detenerse; se suspende la corrida."
            record_error(self, "ERROR", message, response.url)
            raise CloseSpider(f"http_{response.status}")

        try:
            products = json.loads(response.text)
        except json.JSONDecodeError:
            record_error(self, "ERROR", f"Respuesta no JSON en {category_path}", response.url)
            return
        if not isinstance(products, list):
            record_error(self, "ERROR", f"Formato inesperado en {category_path}", response.url)
            return

        checked_at = datetime.now(timezone.utc)
        for product in products:
            offers, warnings = offers_from_product(
                product, store_code=self.store_code, category_slug=slug, checked_at=checked_at,
                internal_sellers=self.internal_sellers,
            )
            for warning in warnings:
                self.crawler.stats.inc_value("offers/skipped")
                self.logger.debug(warning)
            yield from offers

        total = parse_total(response.headers.get("resources"))
        next_offset = offset + PAGE_SIZE
        page_number = offset // PAGE_SIZE + 1
        within_limit = page_number < (self.max_pages or self.scope_pages)
        if products and total and next_offset < min(total, MAX_OFFSET) and within_limit:
            yield self.make_request(category_path, slug, next_offset)
