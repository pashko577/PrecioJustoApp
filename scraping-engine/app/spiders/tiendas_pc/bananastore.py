"""Extractor de Banana Store (bananastore.com.pe).

Listado de categoría `/categorias/detalle/{categoría}/`, 16 productos por página; la página N es
`?cat={categoría}&pag=N`. Cada tarjeta trae el id interno, nombre, enlace, stock y el precio en
dólares con su equivalente en soles calculado por la tienda ("$ 554.85 - (S/ 1,897.60)"); el
botón de compra repite el precio en soles (`data-precio`). Se usa el precio en soles (RN-04).
Sin código de fabricante en el listado: se asocia por puntuación (no crea productos).
"""

from __future__ import annotations

import html as html_lib
import re
from datetime import datetime, timezone

from app.models.offer import ScrapedOffer
from app.normalizers.brands import detect_brand
from app.normalizers.price import parse_price_to_cents
from app.spiders.images import first_image_url
from app.spiders.listing_base import REFURBISHED_RE, ListingSpider
from app.spiders.tiendas_pc.common import soles_cents, split_cards, text

_ID_RE = re.compile(r'data-id="(\d+)"')
_NAME_RE = re.compile(r'<a href="([^"]+)"[^>]*class="[^"]*name-product[^"]*"[^>]*>(.*?)</a>', re.S)
_DATA_PRICE_RE = re.compile(r'data-precio="([\d.]+)"')
_NEW_RE = re.compile(r'class="new-price[^"]*"[^>]*>([^<]*)<')
_OLD_RE = re.compile(r'class="old-price[^"]*"[^>]*>([^<]*)<')
_STOCK_RE = re.compile(r"Stock:\s*([^<]*?)\s*<")
_SOLD_OUT_RE = re.compile(r"agotado|sin stock", re.I)
_TOTAL_RE = re.compile(r"de\s*<span[^>]*>\s*(\d+)\s*</span>\s*productos encontrados")


def _data_price(card: str) -> int | None:
    match = _DATA_PRICE_RE.search(card)
    if not match:
        return None
    try:
        cents = parse_price_to_cents(match.group(1))
    except ValueError:
        return None
    return cents if cents > 0 else None


def parse_listing(page_html: str, *, store_code: str, category_slug: str | None,
                  checked_at: datetime | None = None) -> tuple[list[ScrapedOffer], list[str], int | None]:
    checked_at = checked_at or datetime.now(timezone.utc)
    offers: list[ScrapedOffer] = []
    warnings: list[str] = []
    total_match = _TOTAL_RE.search(page_html)
    total = int(total_match.group(1)) if total_match else None
    for card in split_cards(page_html, '<div class="card-product style-img-border"'):
        id_match, name_match = _ID_RE.search(card), _NAME_RE.search(card)
        if not id_match or not name_match:
            continue
        title = text(name_match.group(2))
        new_match = _NEW_RE.search(card)
        price = (soles_cents(new_match.group(1)) if new_match else None) or _data_price(card)
        if not title or price is None:
            warnings.append(f"{id_match.group(1)}: sin título o sin precio en soles")
            continue
        old_match = _OLD_RE.search(card)
        old = soles_cents(old_match.group(1)) if old_match else None
        stock = _STOCK_RE.search(card)
        if stock:
            available = "OUT_OF_STOCK" if re.match(r"0\b", stock.group(1)) else "AVAILABLE"
        else:
            available = "OUT_OF_STOCK" if _SOLD_OUT_RE.search(card) else "UNKNOWN"
        offers.append(ScrapedOffer(
            store_code=store_code,
            external_product_id=id_match.group(1),
            title=title[:500],
            brand=detect_brand(title),
            model=None,
            price_cents=price,
            list_price_cents=old if old and old > price else None,
            shipping_cents=None,
            availability=available,
            condition="REFURBISHED" if REFURBISHED_RE.search(title) else "NEW",
            seller=None,
            identifiers={},
            category_hint=category_slug,
            product_url=html_lib.unescape(name_match.group(1)),
            image_url=first_image_url(card),
            checked_at=checked_at,
        ))
    return offers, warnings, total


class BananaStoreSpider(ListingSpider):
    """`categoryPaths`: categoría de la tienda ("memoria-ram") -> slug."""

    def page_url(self, path: str, page: int) -> str:
        url = f"{self.base_url}/categorias/detalle/{path}/"
        return url + (f"?cat={path}&pag={page}" if page > 1 else "")

    def parse_body(self, body: str, slug: str):
        return parse_listing(body, store_code=self.store_code, category_slug=slug)
