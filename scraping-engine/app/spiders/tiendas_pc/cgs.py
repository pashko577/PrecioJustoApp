"""Extractor de CGS Computer (cgs-computer.pe).

Listado de categoría `/categorias/?p={id}&cat={nombre}`, 20 productos por página; la página N se
pide con `&pag=` + N en base64 (así lo arma la propia tienda). Cada tarjeta trae el id
(`data-id-product`), nombre, precio en soles ("S/. 890.00"), precio anterior tachado y stock
("Stock: 7 Und", "Stock: +10 Unds" o "Sin Stock"). El listado no trae código de fabricante: sus
publicaciones se asocian por puntuación con productos existentes (no crean productos).
"""

from __future__ import annotations

import base64
import html as html_lib
import re
from datetime import datetime, timezone

from app.models.offer import ScrapedOffer
from app.normalizers.brands import detect_brand
from app.spiders.images import first_image_url
from app.spiders.listing_base import REFURBISHED_RE, ListingSpider
from app.spiders.tiendas_pc.common import soles_cents, split_cards, text

_ID_RE = re.compile(r'data-id-product="(\d+)"')
_NAME_RE = re.compile(r'class="product-name">\s*<a href="([^"]+)"[^>]*>(.*?)</a>', re.S)
_PRICE_RE = re.compile(r'class="product-price\b[^"]*"[^>]*>([^<]*)<')
_OLD_RE = re.compile(r'class="product-price-old"[^>]*>([^<]*)<')
_STOCK_RE = re.compile(r'class="product-card[^"]*"[^>]*>([^<]*)<')
_TOTAL_RE = re.compile(r"Mostrando\s+\d+-\d+\s*<span>\s*de\s+(\d+)")


def availability(stock: str | None) -> str:
    value = (stock or "").strip().lower()
    if not value:
        return "UNKNOWN"
    if "sin stock" in value or "agotado" in value or re.search(r"stock:\s*0\b", value):
        return "OUT_OF_STOCK"
    return "AVAILABLE" if "stock" in value else "UNKNOWN"


def parse_listing(page_html: str, *, store_code: str, base_url: str, category_slug: str | None,
                  checked_at: datetime | None = None) -> tuple[list[ScrapedOffer], list[str], int | None]:
    checked_at = checked_at or datetime.now(timezone.utc)
    offers: list[ScrapedOffer] = []
    warnings: list[str] = []
    total_match = _TOTAL_RE.search(page_html)
    total = int(total_match.group(1)) if total_match else None
    for card in split_cards(page_html, '<div class="product text-center"'):
        id_match, name_match = _ID_RE.search(card), _NAME_RE.search(card)
        if not id_match or not name_match:
            continue
        title = text(name_match.group(2))
        price_match = _PRICE_RE.search(card)
        price = soles_cents(price_match.group(1)) if price_match else None
        if not title or price is None:
            warnings.append(f"{id_match.group(1)}: sin título o sin precio en soles")
            continue
        old_match = _OLD_RE.search(card)
        old = soles_cents(old_match.group(1)) if old_match else None
        stock = _STOCK_RE.search(card)
        # El enlace es relativo a /categorias/ ("detalle/?p=..."); la ficha está en /productos/detalle/.
        href = html_lib.unescape(name_match.group(1))
        url = href if href.startswith("http") else f"{base_url}/productos/{href.lstrip('/')}"
        offers.append(ScrapedOffer(
            store_code=store_code,
            external_product_id=id_match.group(1),
            title=title[:500],
            brand=detect_brand(title),
            model=None,
            price_cents=price,
            list_price_cents=old if old and old > price else None,
            shipping_cents=None,
            availability=availability(stock.group(1) if stock else None),
            condition="REFURBISHED" if REFURBISHED_RE.search(title) else "NEW",
            seller=None,
            identifiers={},
            category_hint=category_slug,
            product_url=url,
            image_url=first_image_url(card, base_url),
            checked_at=checked_at,
        ))
    return offers, warnings, total


class CgsSpider(ListingSpider):
    """`categoryPaths`: consulta del listado ("p=OQ==&cat=Procesadores") -> slug."""

    def page_url(self, path: str, page: int) -> str:
        url = f"{self.base_url}/categorias/?{path}"
        if page > 1:
            url += "&pag=" + base64.b64encode(str(page).encode()).decode()
        return url

    def parse_body(self, body: str, slug: str):
        return parse_listing(body, store_code=self.store_code, base_url=self.base_url, category_slug=slug)
