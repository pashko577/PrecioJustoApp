"""Extractor para tiendas Shopify (MM Store).

Shopify publica el catálogo de cada colección en JSON (`/collections/{colección}/products.json`,
250 productos por página): no hace falta abrir producto por producto. Los precios vienen en la
moneda de la tienda; solo se agregan tiendas que venden en soles (revisado en stores.json).

Cada variante (color, idioma del teclado...) es una publicación aparte: puede tener otro precio
u otra disponibilidad. El SKU solo se usa si es un código de barras válido (EAN/UPC con dígito de
control): los SKU internos ("mms000293") no identifican el producto entre tiendas.
"""

from __future__ import annotations

import json
from datetime import datetime, timezone

from app.models.offer import ScrapedOffer
from app.normalizers.brands import detect_brand
from app.normalizers.identifiers import canonical_gtin
from app.normalizers.price import parse_price_to_cents
from app.spiders.listing_base import REFURBISHED_RE, ListingSpider

PAGE_SIZE = 250


def _cents(value) -> int | None:
    if value in (None, ""):
        return None
    try:
        cents = parse_price_to_cents(str(value))
    except ValueError:
        return None
    return cents if cents > 0 else None


def parse_products(body: str, *, store_code: str, base_url: str, category_slug: str | None,
                   checked_at: datetime | None = None) -> tuple[list[ScrapedOffer], list[str], int | None]:
    checked_at = checked_at or datetime.now(timezone.utc)
    offers: list[ScrapedOffer] = []
    warnings: list[str] = []
    try:
        products = json.loads(body).get("products") or []
    except (ValueError, AttributeError):
        return [], ["respuesta que no es JSON de Shopify"], None
    for product in products:
        title = " ".join(str(product.get("title") or "").split())
        handle = product.get("handle")
        if not title or not handle:
            warnings.append(f"{product.get('id')}: sin título")
            continue
        images = product.get("images") or []
        image = images[0].get("src") if images and isinstance(images[0], dict) else None
        brand = (product.get("vendor") or "").strip() or detect_brand(title)
        variants = product.get("variants") or []
        several = len(variants) > 1
        for variant in variants:
            price = _cents(variant.get("price"))
            if price is None:
                warnings.append(f"{title[:40]}: sin precio")
                continue
            compare = _cents(variant.get("compare_at_price"))
            option = (variant.get("title") or "").strip()
            name = f"{title} - {option}" if several and option and option.lower() != "default title" else title
            gtin = canonical_gtin(variant.get("barcode")) or canonical_gtin(variant.get("sku"))
            url = f"{base_url}/products/{handle}"
            if several:
                url += f"?variant={variant.get('id')}"
            offers.append(ScrapedOffer(
                store_code=store_code,
                external_product_id=str(variant.get("id")),
                title=name[:500],
                brand=brand,
                model=None,
                price_cents=price,
                list_price_cents=compare if compare and compare > price else None,
                shipping_cents=None,
                availability="AVAILABLE" if variant.get("available") else "OUT_OF_STOCK",
                condition="REFURBISHED" if REFURBISHED_RE.search(name) else "NEW",
                seller=None,
                identifiers={"GTIN": gtin} if gtin else {},
                category_hint=category_slug,
                product_url=url,
                image_url=image,
                checked_at=checked_at,
            ))
    return offers, warnings, None


class ShopifySpider(ListingSpider):
    """`categoryPaths`: colección de Shopify (su «handle», por ejemplo "teclados") -> slug."""

    full_page_size = PAGE_SIZE
    custom_settings = {**ListingSpider.custom_settings, "DOWNLOAD_DELAY": 4}

    def page_url(self, path: str, page: int) -> str:
        return f"{self.base_url}/collections/{path}/products.json?limit={PAGE_SIZE}&page={page}"

    def parse_body(self, body: str, slug: str):
        return parse_products(body, store_code=self.store_code, base_url=self.base_url, category_slug=slug)
