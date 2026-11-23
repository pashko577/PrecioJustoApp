"""Extractor genérico para tiendas Magento (Efe, La Curacao).

Lee los listados de categoría (HTML generado en el servidor), que traen datos estructurados
en atributos: `data-product-sku` (modelo del fabricante), `data-price-amount` con
`data-price-type="finalPrice"` / `"oldPrice"`, y el formulario de carrito solo si hay stock.

Reglas de extracción responsable (PRECIO_JUSTO.md, 7.7): respeta robots.txt (no usa
`product_list_limit` ni otros parámetros bloqueados), una solicitud a la vez con pausa, y se
DETIENE ante HTTP 403/429 o desafíos de Cloudflare (no los evade).
"""

from __future__ import annotations

import html as html_lib
import os
import re
from datetime import datetime, timezone

import scrapy
from scrapy.exceptions import CloseSpider

from app.models.offer import ScrapedOffer
from app.normalizers.brands import detect_brand
from app.normalizers.identifiers import canonical_mpn
from app.normalizers.price import number_to_cents
from app.pipelines.job_errors import record_error
from app.spiders.vtex.base import is_due

STOP_STATUSES = (403, 429, 503)
MAX_PAGES_PER_CATEGORY = 60  # tope de seguridad (24 productos por página)

_ITEM_SPLIT = re.compile(r'<li class="item product product-item')
_LINK_RE = re.compile(r'class="product-item-link"[^>]*href="([^"]+)"[^>]*>\s*([^<]+?)\s*<|'
                      r'href="([^"]+)"[^>]*class="product-item-link"[^>]*>\s*([^<]+?)\s*<')
_SKU_RE = re.compile(r'data-product-sku="([^"]+)"')
_ID_RE = re.compile(r'data-product-id="(\d+)"')
_PRICE_RE = re.compile(r'data-price-amount="([\d.]+)"\s+data-price-type="(finalPrice|oldPrice)"')
_TOTAL_RE = re.compile(r'<span class="toolbar-number">(\d+)</span>')
_REFURBISHED_RE = re.compile(r"reacondicionad|refurbished|open box|seminuevo|exhibici[oó]n", re.I)
_CHALLENGE_RE = re.compile(r"cf-chl|challenge-platform|Just a moment|Attention Required", re.I)


def parse_listing(page_html: str, *, store_code: str, category_slug: str | None,
                  checked_at: datetime | None = None) -> tuple[list[ScrapedOffer], list[str], int | None]:
    """Convierte un listado de categoría en ofertas. Devuelve `(ofertas, avisos, total_productos)`."""
    checked_at = checked_at or datetime.now(timezone.utc)
    offers: list[ScrapedOffer] = []
    warnings: list[str] = []
    totals = [int(n) for n in _TOTAL_RE.findall(page_html)]
    total = max(totals) if totals else None

    # Solo la lista de productos: evita tomar precios de bloques como "vistos recientemente".
    start = page_html.find('<ol class="products list items product-items')
    end = page_html.find("</ol>", start) if start >= 0 else -1
    region = page_html[start:end] if start >= 0 and end > start else ""

    for chunk in _ITEM_SPLIT.split(region)[1:]:
        link = _LINK_RE.search(chunk)
        sku = _SKU_RE.search(chunk)
        pid = _ID_RE.search(chunk)
        if not link or not (sku or pid):
            warnings.append("producto sin enlace o sin identificador")
            continue
        url = html_lib.unescape(link.group(1) or link.group(3))
        title = html_lib.unescape(link.group(2) or link.group(4)).strip()
        prices: dict[str, str] = {}
        for amount, kind in _PRICE_RE.findall(chunk):
            prices.setdefault(kind, amount)  # el primero de cada tipo es el del producto
        price_cents = number_to_cents(prices.get("finalPrice"))
        if price_cents is None:
            warnings.append(f"{title[:40]}: sin precio")
            continue
        old_cents = number_to_cents(prices.get("oldPrice"))
        in_stock = 'data-role="tocart-form"' in chunk
        if not in_stock and re.search(r"agotado|stock unavailable|out of stock", chunk, re.I):
            availability = "OUT_OF_STOCK"
        else:
            availability = "AVAILABLE" if in_stock else "UNKNOWN"
        model = sku.group(1).strip() if sku else None
        offers.append(ScrapedOffer(
            store_code=store_code,
            external_product_id=(pid.group(1) if pid else model).replace("/", "-"),
            title=title,
            brand=detect_brand(title),
            model=model,
            price_cents=price_cents,
            list_price_cents=old_cents if old_cents and old_cents > price_cents else None,
            shipping_cents=None,
            availability=availability,
            condition="REFURBISHED" if _REFURBISHED_RE.search(title) else "NEW",
            seller=None,
            identifiers={"MPN": canonical_mpn(model)} if canonical_mpn(model) else {},
            category_hint=category_slug,
            product_url=url,
            image_url=None,
            checked_at=checked_at,
        ))
    return offers, warnings, total


class MagentoSpider(scrapy.Spider):
    """Base: cada tienda define `store_code`, `base_url` y `categories` (ruta .html -> slug)."""

    store_code: str = ""
    base_url: str = ""
    categories: dict[str, str] = {}

    handle_httpstatus_list = list(STOP_STATUSES)
    custom_settings = {
        "DOWNLOAD_DELAY": 6,
        "CONCURRENT_REQUESTS_PER_DOMAIN": 1,
        "RETRY_HTTP_CODES": [500, 502, 504, 522, 524, 408],
    }

    def __init__(self, *args, max_pages: int | str | None = None, **kwargs):
        super().__init__(*args, **kwargs)
        self.max_pages = int(max_pages) if max_pages else None
        self.job_errors: list[dict] = []
        self.stopped_early = False
        self.not_due = False

    def page_url(self, path: str, page: int) -> str:
        return f"{self.base_url}{path}" + (f"?p={page}" if page > 1 else "")

    def make_request(self, path: str, slug: str, page: int) -> scrapy.Request:
        return scrapy.Request(self.page_url(path, page), callback=self.parse_page,
                              cb_kwargs={"path": path, "slug": slug, "page": page})

    def _store_is_due(self) -> bool:
        if os.getenv("JOB_TYPE") != "SCHEDULED":
            return True
        from app.firebase_client import get_db

        snap = get_db().collection("stores").document(self.store_code).get()
        return is_due(snap.to_dict() if snap.exists else None)

    async def start(self):
        if not self._store_is_due():
            self.not_due = True
            self.logger.info("%s: todavía no toca según su frecuencia; no se hacen solicitudes.", self.store_code)
            return
        for path, slug in self.categories.items():
            yield self.make_request(path, slug, 1)

    def parse_page(self, response, path: str, slug: str, page: int):
        body = response.text if hasattr(response, "text") else ""
        if response.status in STOP_STATUSES or _CHALLENGE_RE.search(body[:5000]):
            self.stopped_early = True
            message = f"HTTP {response.status} o desafío anti-bots en {path}: se suspende la corrida (no se evade)."
            record_error(self, "ERROR", message, response.url)
            raise CloseSpider(f"blocked_{response.status}")

        offers, warnings, total = parse_listing(body, store_code=self.store_code, category_slug=slug)
        for warning in warnings:
            self.crawler.stats.inc_value("offers/skipped")
            self.logger.debug(warning)
        yield from offers

        per_page = max(len(offers) + len(warnings), 1)
        within_limit = page < (self.max_pages or MAX_PAGES_PER_CATEGORY)
        if offers and total and page * per_page < total and within_limit:
            yield self.make_request(path, slug, page + 1)
