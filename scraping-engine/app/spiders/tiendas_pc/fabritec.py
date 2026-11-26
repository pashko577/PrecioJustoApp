"""Extractor de Fabritec (fabritec.pe).

La página de categoría (`/productos-filtros?category=9&subcategory=30`) carga los productos con
una consulta pública de la propia tienda: `/ajax/public/products?page=N&categories[]=9&
subcategories[]=30`, que devuelve JSON con el HTML de las tarjetas y la paginación (robots.txt
solo restringe /admin). Cada tarjeta trae el id, marca, nombre (con el número de parte entre
paréntesis: "Procesador ... (BX8071512400-OEM) ..."), precio en soles y en dólares, y el botón
de compra desactivado ("Sin stock") cuando está agotado.
"""

from __future__ import annotations

import html as html_lib
import json
import re
from datetime import datetime, timezone

from app.models.offer import ScrapedOffer
from app.normalizers.brands import detect_brand
from app.normalizers.identifiers import canonical_mpn
from app.spiders.images import first_image_url
from app.spiders.listing_base import REFURBISHED_RE, ListingSpider
from app.spiders.tiendas_pc.common import soles_cents, split_cards, text
from app.spiders.vtex.base import looks_like_model_code

_ID_RE = re.compile(r'data-product-id="(\d+)"')
_TITLE_RE = re.compile(r'<a class="[^"]*titulo_producto_card[^"]*"\s+href="([^"]+)"[^>]*>(.*?)</a>', re.S)
_BRAND_RE = re.compile(r'<a class="font-xs color-gray-500"\s+href="[^"]*">([^<]*)</a>')
_PRICE_RE = re.compile(r'class="[^"]*price-main[^"]*"[^>]*>([^<]*)<')
_SOLD_OUT_RE = re.compile(r"Sin stock|Agotado", re.I)
_PAGE_RE = re.compile(r'data-page="(\d+)"')
# Número de parte entre paréntesis: "(BX8071512400-OEM)", "(RZ01-03850100-R3U1)".
_PART_RE = re.compile(r"\(([A-Za-z0-9][A-Za-z0-9#/._-]{4,30})\)")


def part_number(title: str) -> str | None:
    for candidate in _PART_RE.findall(title):
        if looks_like_model_code(candidate):
            return candidate
    return None


def parse_response(body: str, *, store_code: str, category_slug: str | None, page: int = 1,
                   checked_at: datetime | None = None) -> tuple[list[ScrapedOffer], list[str], int | None]:
    checked_at = checked_at or datetime.now(timezone.utc)
    try:
        data = json.loads(body)
    except ValueError:
        return [], ["respuesta que no es JSON de Fabritec"], None
    cards_html, pagination = data.get("html") or "", data.get("pagination") or ""
    offers: list[ScrapedOffer] = []
    warnings: list[str] = []
    cards = split_cards(cards_html, '<div class="card-grid-style-3')
    for card in cards:
        id_match, title_match = _ID_RE.search(card), _TITLE_RE.search(card)
        if not id_match or not title_match:
            continue
        title = text(title_match.group(2))
        price_match = _PRICE_RE.search(card)
        price = soles_cents(price_match.group(1)) if price_match else None
        if not title or price is None:
            warnings.append(f"{id_match.group(1)}: sin título o sin precio en soles")
            continue
        brand_match = _BRAND_RE.search(card)
        brand = text(brand_match.group(1)) if brand_match else ""
        model = part_number(title)
        mpn = canonical_mpn(model)
        offers.append(ScrapedOffer(
            store_code=store_code,
            external_product_id=id_match.group(1),
            title=title[:500],
            brand=brand or detect_brand(title),
            model=model,
            price_cents=price,
            list_price_cents=None,
            shipping_cents=None,
            availability="OUT_OF_STOCK" if _SOLD_OUT_RE.search(card) else "AVAILABLE",
            condition="REFURBISHED" if REFURBISHED_RE.search(title) else "NEW",
            seller=None,
            identifiers={"MPN": mpn} if mpn else {},
            category_hint=category_slug,
            product_url=html_lib.unescape(title_match.group(1)),
            image_url=first_image_url(card),
            checked_at=checked_at,
        ))
    # La paginación solo enlaza páginas: el total se estima con la última página enlazada.
    pages = [int(p) for p in _PAGE_RE.findall(pagination)]
    last = max(pages + [page])
    total = last * max(len(cards), 1) if cards else None
    return offers, warnings, total


class FabritecSpider(ListingSpider):
    """`categoryPaths`: "categoría/subcategoría" de la tienda ("9/30") -> slug."""

    def page_url(self, path: str, page: int) -> str:
        category, _, subcategory = path.partition("/")
        url = f"{self.base_url}/ajax/public/products?page={page}&has_category_context=true&categories%5B%5D={category}"
        return url + (f"&subcategories%5B%5D={subcategory}" if subcategory else "")

    def make_request(self, path: str, slug: str, page: int):
        request = super().make_request(path, slug, page)
        return request.replace(headers={"X-Requested-With": "XMLHttpRequest", "Accept": "application/json"})

    def parse_page(self, response, path: str, slug: str, page: int):
        self._page = page
        yield from super().parse_page(response, path, slug, page)

    def parse_body(self, body: str, slug: str):
        return parse_response(body, store_code=self.store_code, category_slug=slug, page=getattr(self, "_page", 1))
