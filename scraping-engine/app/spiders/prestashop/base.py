"""Extractor genérico para tiendas PrestaShop (SercoPlus).

Lee los listados de categoría (HTML generado en el servidor). Cada producto es un
`<article ... data-id-product="N">` dentro de `#js-product-list`. SercoPlus publica el precio en
dólares con su equivalente en soles calculado por la propia tienda: "$ 860,80 (S/ 3.030,02)".
Se toma el precio en soles (la app compara en PEN, RN-04); sin precio en soles se omite.

No publica código de fabricante ni código de barras en el listado (el `itemprop="mpn"` es un
valor de relleno): estas publicaciones se asocian por puntuación a productos existentes y no
crean productos nuevos.
"""

from __future__ import annotations

import html as html_lib
import re
from datetime import datetime, timezone

from app.models.offer import ScrapedOffer
from app.normalizers.brands import detect_brand
from app.normalizers.price import parse_price_to_cents
from app.spiders.listing_base import REFURBISHED_RE, ListingSpider

_ARTICLE_RE = re.compile(r'<article[^>]*data-id-product="(\d+)"')
_TITLE_RE = re.compile(r'class="[^"]*product-title[^"]*">\s*<a href="([^"]+)"[^>]*>\s*<h\d[^>]*>([^<]+)</h\d>')
_PRICE_RE = re.compile(r'<span class="price"[^>]*>([^<]*)</span>')
_REGULAR_RE = re.compile(r'<span class="regular-price"[^>]*>([^<]*)</span>')
_SOLES_RE = re.compile(r"S/[\s\xa0]*([\d.,]+)")
_STOCK_RE = re.compile(r'Stock:\s*</label>\s*<span class="value">([^<]*)</span>')
_TOTAL_RE = re.compile(r"Mostrando\s+\d+-\d+\s+de\s+(\d+)")


def soles_cents(text: str | None) -> int | None:
    """Precio en soles de un texto como "$ 860,80 (S/ 3.030,02)"; None si no hay soles."""
    match = _SOLES_RE.search(html_lib.unescape(text or ""))
    if not match:
        return None
    try:
        return parse_price_to_cents(match.group(1))
    except ValueError:
        return None


def availability_from_stock(stock: str | None) -> str:
    value = (html_lib.unescape(stock or "")).strip().lower()
    if not value:
        return "UNKNOWN"
    if value in ("0", "agotado") or value.startswith("0 "):
        return "OUT_OF_STOCK"
    return "AVAILABLE"  # "1", "8", "Mayor a 10", "> 10"


def parse_listing(page_html: str, *, store_code: str, category_slug: str | None,
                  checked_at: datetime | None = None) -> tuple[list[ScrapedOffer], list[str], int | None]:
    checked_at = checked_at or datetime.now(timezone.utc)
    offers: list[ScrapedOffer] = []
    warnings: list[str] = []
    total_match = _TOTAL_RE.search(page_html)
    total = int(total_match.group(1)) if total_match else None

    # Solo la lista de productos: los bloques laterales ("destacados") también tienen precios.
    start = page_html.find('id="js-product-list"')
    region = page_html[start:] if start >= 0 else ""
    matches = list(_ARTICLE_RE.finditer(region))
    for i, match in enumerate(matches):
        chunk = region[match.start(): matches[i + 1].start() if i + 1 < len(matches) else len(region)]
        product_id = match.group(1)
        title_match = _TITLE_RE.search(chunk)
        if not title_match:
            warnings.append(f"{product_id}: sin título")
            continue
        url = html_lib.unescape(title_match.group(1))
        title = re.sub(r"\s+", " ", html_lib.unescape(title_match.group(2))).strip()
        price_cents = next((c for c in map(soles_cents, _PRICE_RE.findall(chunk)) if c), None)
        if price_cents is None:
            warnings.append(f"{title[:40]}: sin precio en soles")
            continue
        regular = _REGULAR_RE.search(chunk)
        list_cents = soles_cents(regular.group(1)) if regular else None
        stock = _STOCK_RE.search(chunk)
        offers.append(ScrapedOffer(
            store_code=store_code,
            external_product_id=product_id,
            title=title,
            brand=detect_brand(title),
            model=None,
            price_cents=price_cents,
            list_price_cents=list_cents if list_cents and list_cents > price_cents else None,
            shipping_cents=None,
            availability=availability_from_stock(stock.group(1) if stock else None),
            condition="REFURBISHED" if REFURBISHED_RE.search(title) else "NEW",
            seller=None,
            identifiers={},
            category_hint=category_slug,
            product_url=url,
            image_url=None,
            checked_at=checked_at,
        ))
    return offers, warnings, total


class PrestaShopSpider(ListingSpider):
    """Base PrestaShop: paginación con `?page=N`."""

    def page_url(self, path: str, page: int) -> str:
        return f"{self.base_url}{path}" + (f"?page={page}" if page > 1 else "")

    def parse_body(self, body: str, slug: str):
        return parse_listing(body, store_code=self.store_code, category_slug=slug)
