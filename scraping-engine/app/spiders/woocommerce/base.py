"""Extractor para tiendas WooCommerce (Miau Gaming).

WooCommerce trae una API pública de solo lectura de la propia tienda (Store API,
`/wp-json/wc/store/v1/products`): lista los productos de una categoría con precio, moneda,
stock y marca, 100 por página. Solo se aceptan precios en soles (`currency_code` = PEN).

Los precios vienen en la unidad mínima de la moneda (`currency_minor_unit`: 2 = céntimos).
"""

from __future__ import annotations

import html as html_lib
import json
from datetime import datetime, timezone

from app.models.offer import ScrapedOffer
from app.normalizers.brands import detect_brand
from app.normalizers.identifiers import canonical_gtin, canonical_mpn
from app.spiders.listing_base import REFURBISHED_RE, ListingSpider
from app.spiders.vtex.base import looks_like_model_code

PAGE_SIZE = 100


def _cents(prices: dict, key: str) -> int | None:
    raw = prices.get(key)
    if raw in (None, ""):
        return None
    try:
        minor = int(prices.get("currency_minor_unit", 2))
        value = int(str(raw))
    except (TypeError, ValueError):
        return None
    cents = value * 10 ** (2 - minor) if minor <= 2 else value // 10 ** (minor - 2)
    return cents if cents > 0 else None


def parse_products(body: str, *, store_code: str, category_slug: str | None,
                   checked_at: datetime | None = None) -> tuple[list[ScrapedOffer], list[str], int | None]:
    checked_at = checked_at or datetime.now(timezone.utc)
    offers: list[ScrapedOffer] = []
    warnings: list[str] = []
    try:
        products = json.loads(body)
    except ValueError:
        return [], ["respuesta que no es JSON de WooCommerce"], None
    if not isinstance(products, list):
        return [], ["respuesta inesperada de WooCommerce"], None
    for product in products:
        title = " ".join(html_lib.unescape(str(product.get("name") or "")).split())
        prices = product.get("prices") or {}
        if not title:
            warnings.append(f"{product.get('id')}: sin título")
            continue
        if prices.get("currency_code") != "PEN":
            warnings.append(f"{title[:40]}: precio en {prices.get('currency_code')}, no en soles")
            continue
        price = _cents(prices, "price")
        if price is None:
            warnings.append(f"{title[:40]}: sin precio")
            continue
        regular = _cents(prices, "regular_price")
        brands = product.get("brands") or []
        brand = (brands[0].get("name") if brands and isinstance(brands[0], dict) else None) or detect_brand(title)
        sku = (product.get("sku") or "").strip()
        gtin = canonical_gtin(sku)
        mpn = canonical_mpn(sku) if not gtin and looks_like_model_code(sku) else None
        images = product.get("images") or []
        offers.append(ScrapedOffer(
            store_code=store_code,
            external_product_id=str(product.get("id")),
            title=title[:500],
            brand=brand,
            model=sku if mpn else None,
            price_cents=price,
            list_price_cents=regular if regular and regular > price else None,
            shipping_cents=None,
            availability="AVAILABLE" if product.get("is_in_stock") else "OUT_OF_STOCK",
            condition="REFURBISHED" if REFURBISHED_RE.search(title) else "NEW",
            seller=None,
            identifiers={k: v for k, v in (("GTIN", gtin), ("MPN", mpn)) if v},
            category_hint=category_slug,
            product_url=product.get("permalink") or "",
            image_url=images[0].get("src") if images and isinstance(images[0], dict) else None,
            checked_at=checked_at,
        ))
    return offers, warnings, None


class WooCommerceSpider(ListingSpider):
    """`categoryPaths`: id de la categoría de WooCommerce (por ejemplo "138") -> slug."""

    full_page_size = PAGE_SIZE
    custom_settings = {**ListingSpider.custom_settings, "DOWNLOAD_DELAY": 4}

    def page_url(self, path: str, page: int) -> str:
        return f"{self.base_url}/wp-json/wc/store/v1/products?category={path}&per_page={PAGE_SIZE}&page={page}"

    def parse_body(self, body: str, slug: str):
        return parse_products(body, store_code=self.store_code, category_slug=slug)
