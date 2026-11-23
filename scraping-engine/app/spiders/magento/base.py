"""Extractor genérico para tiendas Magento (Efe, La Curacao).

Lee los listados de categoría (HTML generado en el servidor), que traen datos estructurados
en atributos: `data-product-sku` (modelo del fabricante), `data-price-amount` con
`data-price-type="finalPrice"` / `"oldPrice"`, y el formulario de carrito solo si hay stock.

Reglas de extracción responsable en `app/spiders/listing_base.py`; además respeta robots.txt
(no usa `product_list_limit` ni otros parámetros bloqueados).
"""

from __future__ import annotations

import html as html_lib
import re
from datetime import datetime, timezone

from app.models.offer import ScrapedOffer
from app.normalizers.brands import detect_brand
from app.normalizers.identifiers import canonical_mpn
from app.normalizers.price import number_to_cents
from app.spiders.listing_base import REFURBISHED_RE, ListingSpider

_LIST_START_RE = re.compile(r'<ol class="[^"]*\bproducts list items product-items')
_ITEM_SPLIT = re.compile(r'<li class="item product product-item')
_LINK_RE = re.compile(r'class="product-item-link"[^>]*href="([^"]+)"[^>]*>\s*([^<]+?)\s*<|'
                      r'href="([^"]+)"[^>]*class="product-item-link"[^>]*>\s*([^<]+?)\s*<')
_SKU_RE = re.compile(r'data-product-sku="([^"]+)"')
_ID_RE = re.compile(r'data-product-id="(\d+)"')
_PRICE_RE = re.compile(r'data-price-amount="([\d.]+)"\s+data-price-type="(finalPrice|oldPrice)"')
_TOTAL_RE = re.compile(r'<span class="toolbar-number">(\d+)</span>')


def parse_listing(page_html: str, *, store_code: str, category_slug: str | None,
                  checked_at: datetime | None = None) -> tuple[list[ScrapedOffer], list[str], int | None]:
    """Convierte un listado de categoría en ofertas. Devuelve `(ofertas, avisos, total_productos)`."""
    checked_at = checked_at or datetime.now(timezone.utc)
    offers: list[ScrapedOffer] = []
    warnings: list[str] = []
    totals = [int(n) for n in _TOTAL_RE.findall(page_html)]
    total = max(totals) if totals else None

    # Solo la lista de productos: evita tomar precios de bloques como "vistos recientemente".
    # Algunos temas agregan clases antes ("filterproducts products list items ...", Phantom).
    list_start = _LIST_START_RE.search(page_html)
    start = list_start.start() if list_start else -1
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
            condition="REFURBISHED" if REFURBISHED_RE.search(title) else "NEW",
            seller=None,
            identifiers={"MPN": canonical_mpn(model)} if canonical_mpn(model) else {},
            category_hint=category_slug,
            product_url=url,
            image_url=None,
            checked_at=checked_at,
        ))
    return offers, warnings, total


class MagentoSpider(ListingSpider):
    """Base Magento: paginación con `?p=N` (sin `product_list_limit`, bloqueado por robots.txt)."""

    def page_url(self, path: str, page: int) -> str:
        return f"{self.base_url}{path}" + (f"?p={page}" if page > 1 else "")

    def parse_body(self, body: str, slug: str):
        return parse_listing(body, store_code=self.store_code, category_slug=slug)
