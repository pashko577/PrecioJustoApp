"""Extractor de Memory Kings (sitio propio).

Sus categorías se dividen en "listados" (`/listados/258/laptops-core-i5`) que muestran todos sus
productos en una sola página. `categoryPaths` en stores.json mapea listados concretos a nuestras
categorías (se eligen a mano para no mezclar accesorios, TVs o discos para servidores). Un producto
que aparece en varios listados se envía una sola vez por corrida (ver `ListingSpider`).

Precio publicado en dólares y soles por la tienda: "$ 680.00 ó S/ 2,366.00"; se toma el de soles.
No publica código de fabricante ni de barras: solo se asocia por puntuación a productos existentes.
robots.txt solo bloquea `/resultados/` (buscador), que no se usa.
"""

from __future__ import annotations

import html as html_lib
import re
from datetime import datetime, timezone

from app.models.offer import ScrapedOffer
from app.normalizers.brands import detect_brand
from app.spiders.listing_base import REFURBISHED_RE, ListingSpider
from app.spiders.prestashop.base import availability_from_stock, soles_cents
from app.spiders.images import first_image_url

_CARD_RE = re.compile(r'<a href="((?:https://www\.memorykings\.pe)?/producto/(\d+)/[^"]+)"')
_TITLE_RE = re.compile(r"<h4[^>]*>([^<]+)</h4>")
_PRICE_RE = re.compile(r'<div class="price">([^<]*)</div>')
_BEFORE_RE = re.compile(r'<div class="price-before">([^<]*)</div>')
_STOCK_RE = re.compile(r'<div class="stock">\s*Stock:\s*<b>([^<]*)</b>')
_TOTAL_RE = re.compile(r"Mostrando\s*<b>(\d+)</b>\s*productos")
_SPECS_RE = re.compile(r"\b(\d{1,3})\|(\d{3,4}|\d(?:\.\d)?TB)\|(\d{2}(?:\.\d)?)(?:\"|”|'')?", re.I)
BASE = "https://www.memorykings.pe"


def expand_specs(title: str) -> str:
    """'16|512|15.6"' (RAM|almacenamiento|pantalla) -> '16GB 512GB 15.6"'.

    Con unidades, el matching compara capacidades igual que en las demás tiendas (8.3).
    """
    def repl(m: re.Match) -> str:
        storage = m.group(2).upper() if m.group(2).upper().endswith("TB") else f"{m.group(2)}GB"
        return f'{m.group(1)}GB {storage} {m.group(3)}"'
    return _SPECS_RE.sub(repl, title)


def parse_listing(page_html: str, *, store_code: str, category_slug: str | None,
                  checked_at: datetime | None = None) -> tuple[list[ScrapedOffer], list[str], int | None]:
    checked_at = checked_at or datetime.now(timezone.utc)
    offers: list[ScrapedOffer] = []
    warnings: list[str] = []
    total_match = _TOTAL_RE.search(page_html)
    total = int(total_match.group(1)) if total_match else None

    # Solo la grilla de productos (los banners superiores también enlazan productos).
    start = page_html.find('<ul class="products')
    end = page_html.find("</ul>", start) if start >= 0 else -1
    region = page_html[start:end] if start >= 0 and end > start else ""
    cards = list(_CARD_RE.finditer(region))
    for i, card in enumerate(cards):
        chunk = region[card.start(): cards[i + 1].start() if i + 1 < len(cards) else len(region)]
        url = html_lib.unescape(card.group(1))
        url = url if url.startswith("http") else BASE + url
        title_match = _TITLE_RE.search(chunk)
        if not title_match:
            warnings.append(f"{card.group(2)}: sin título")
            continue
        title = expand_specs(re.sub(r"\s+", " ", html_lib.unescape(title_match.group(1))).strip())
        price = _PRICE_RE.search(chunk)
        price_cents = soles_cents(price.group(1)) if price else None
        if price_cents is None:
            warnings.append(f"{title[:40]}: sin precio en soles")
            continue
        before = _BEFORE_RE.search(chunk)
        before_cents = soles_cents(before.group(1)) if before else None
        stock = _STOCK_RE.search(chunk)
        offers.append(ScrapedOffer(
            store_code=store_code,
            external_product_id=card.group(2),
            title=title,
            brand=detect_brand(title),
            model=None,
            price_cents=price_cents,
            list_price_cents=before_cents if before_cents and before_cents > price_cents else None,
            shipping_cents=None,
            availability=availability_from_stock(stock.group(1) if stock else None),
            condition="REFURBISHED" if REFURBISHED_RE.search(title) else "NEW",
            seller=None,
            identifiers={},
            category_hint=category_slug,
            product_url=url,
            image_url=first_image_url(chunk, BASE),
            checked_at=checked_at,
        ))
    return offers, warnings, total


class MemoryKingsSpider(ListingSpider):
    """Cada listado es una sola página: no hay paginación."""

    def page_url(self, path: str, page: int) -> str:
        return f"{self.base_url}{path}"

    def parse_body(self, body: str, slug: str):
        offers, warnings, _ = parse_listing(body, store_code=self.store_code, category_slug=slug)
        return offers, warnings, None  # sin total: no pide más páginas
