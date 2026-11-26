"""Extractor por mapa del sitio + ficha de producto (Unik Store).

Para tiendas cuyo listado no se puede recorrer (Unik: robots.txt prohíbe las URLs con `?`, y
la paginación de sus categorías es `?page=N`). Se lee `sitemap.xml` (permitido y publicado por la
tienda), se eligen las fichas de nuestras categorías por el nombre de la URL
(`categoryPaths`: expresión regular sobre el final de la URL -> slug, en orden) y se abre cada
ficha una por una. La ficha trae los datos estructurados de schema.org (`application/ld+json`,
los mismos que lee Google): nombre, marca, SKU (en Unik es el código del fabricante), precio en
soles y disponibilidad.

Es más lento que un listado (una solicitud por producto), por eso la tienda se actualiza una vez
al día. Opciones en stores.json: `productPathPrefix` (por ejemplo "/producto/").
"""

from __future__ import annotations

import html as html_lib
import json
import re
from datetime import datetime, timezone
from urllib.parse import urlparse

import scrapy

from app.models.offer import ScrapedOffer
from app.normalizers.brands import detect_brand
from app.normalizers.identifiers import canonical_gtin, canonical_mpn
from app.normalizers.price import parse_price_to_cents
from app.spiders.listing_base import REFURBISHED_RE, ListingSpider
from app.spiders.vtex.base import looks_like_model_code

_LOC_RE = re.compile(r"<loc>\s*([^<\s]+)\s*</loc>")
_LD_RE = re.compile(r'<script[^>]*type="application/ld\+json"[^>]*>(.*?)</script>', re.S | re.I)
# Con MAX_PAGES (corrida manual de prueba) se abren a lo más MAX_PAGES × esto fichas por categoría.
PRODUCTS_PER_TEST_PAGE = 5


def sitemap_products(body: str, prefix: str, patterns: dict[str, str]) -> list[tuple[str, str]]:
    """(URL, slug) de las fichas del sitemap que corresponden a nuestras categorías."""
    compiled = [(re.compile(pattern, re.I), slug) for pattern, slug in patterns.items()]
    found: list[tuple[str, str]] = []
    seen: set[str] = set()
    for loc in _LOC_RE.findall(body):
        url = html_lib.unescape(loc)
        path = urlparse(url).path
        if not path.startswith(prefix) or url in seen:
            continue
        name = path[len(prefix):].strip("/")
        for regex, slug in compiled:
            if regex.search(name):
                found.append((url, slug))
                seen.add(url)
                break
    return found


def _ld_products(page_html: str) -> list[dict]:
    products: list[dict] = []
    for raw in _LD_RE.findall(page_html):
        try:
            data = json.loads(raw.strip(), strict=False)
        except ValueError:
            continue
        stack = data if isinstance(data, list) else [data]
        while stack:
            node = stack.pop(0)
            if not isinstance(node, dict):
                continue
            if node.get("@type") == "Product" or (isinstance(node.get("@type"), list) and "Product" in node["@type"]):
                products.append(node)
            stack.extend(node.get("@graph") or [])
    return products


def _first(value):
    return value[0] if isinstance(value, list) and value else value


def parse_product_page(page_html: str, *, store_code: str, url: str, category_slug: str | None,
                       checked_at: datetime | None = None) -> tuple[ScrapedOffer | None, str | None]:
    """(oferta, None) o (None, motivo) a partir de los datos schema.org de la ficha."""
    checked_at = checked_at or datetime.now(timezone.utc)
    products = _ld_products(page_html)
    if not products:
        return None, "sin datos de producto (schema.org)"
    product = products[0]
    title = " ".join(html_lib.unescape(str(product.get("name") or "")).split())
    offer = _first(product.get("offers")) or {}
    if not title or not isinstance(offer, dict):
        return None, "sin nombre u oferta"
    if (offer.get("priceCurrency") or "PEN") != "PEN":
        return None, f"precio en {offer.get('priceCurrency')}, no en soles"
    try:
        price = parse_price_to_cents(str(offer.get("price")))
    except ValueError:
        return None, "sin precio"
    if price <= 0:
        return None, "sin precio"
    availability = str(offer.get("availability") or "")
    if availability.endswith(("InStock", "LimitedAvailability", "OnlineOnly")):
        status = "AVAILABLE"
    elif availability.endswith(("OutOfStock", "SoldOut", "Discontinued")):
        status = "OUT_OF_STOCK"
    elif availability.endswith(("PreOrder", "BackOrder")):
        status = "PREORDER"
    else:
        status = "UNKNOWN"
    brand = _first(product.get("brand"))
    brand_name = (brand.get("name") if isinstance(brand, dict) else brand) or detect_brand(title)
    sku = str(product.get("sku") or product.get("mpn") or "").strip()
    gtin = next((canonical_gtin(str(product.get(k))) for k in ("gtin13", "gtin12", "gtin14", "gtin8", "gtin")
                 if product.get(k) and canonical_gtin(str(product.get(k)))), None)
    model = sku if looks_like_model_code(sku) else None
    mpn = canonical_mpn(model)
    image = _first(product.get("image"))
    slug = urlparse(url).path.rstrip("/").rsplit("/", 1)[-1]
    return ScrapedOffer(
        store_code=store_code,
        external_product_id=slug[:200],
        title=title[:500],
        brand=str(brand_name).strip() if brand_name else None,
        model=model,
        price_cents=price,
        list_price_cents=None,
        shipping_cents=None,
        availability=status,
        condition="REFURBISHED" if REFURBISHED_RE.search(title) else "NEW",
        seller=None,
        identifiers={k: v for k, v in (("GTIN", gtin), ("MPN", mpn)) if v},
        category_hint=category_slug,
        product_url=url,
        image_url=image if isinstance(image, str) and image.startswith("http") else None,
        checked_at=checked_at,
    ), None


class SitemapProductsSpider(ListingSpider):
    """`categoryPaths`: expresión regular sobre el nombre de la ficha ("^procesador") -> slug."""

    custom_settings = {**ListingSpider.custom_settings, "DOWNLOAD_DELAY": 4}

    async def start(self):
        if getattr(self, "not_due", False):
            return
        if not self._store_is_due():
            self.not_due = True
            self.logger.info("%s: todavía no toca según su frecuencia; no se hacen solicitudes.", self.store_code)
            return
        yield scrapy.Request(f"{self.base_url}/sitemap.xml", callback=self.parse_sitemap)

    def parse_sitemap(self, response):
        body = self.stop_if_blocked(response, "sitemap.xml")
        prefix = self.store_config.get("productPathPrefix", "/producto/")
        found = sitemap_products(body, prefix, self.categories)
        if self.max_pages:
            per_category: dict[str, int] = {}
            limited = []
            for url, slug in found:
                per_category[slug] = per_category.get(slug, 0) + 1
                if per_category[slug] <= self.max_pages * PRODUCTS_PER_TEST_PAGE:
                    limited.append((url, slug))
            found = limited
        self.logger.info("%s: %d fichas de nuestras categorías en el sitemap.", self.store_code, len(found))
        for url, slug in found:
            yield scrapy.Request(url, callback=self.parse_product, cb_kwargs={"slug": slug})

    def parse_product(self, response, slug: str):
        body = self.stop_if_blocked(response, response.url)
        offer, problem = parse_product_page(body, store_code=self.store_code, url=response.url, category_slug=slug)
        yield from self.emit([offer] if offer else [], [f"{response.url}: {problem}"] if problem else [])
