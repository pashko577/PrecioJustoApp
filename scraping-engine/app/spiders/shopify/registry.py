"""Spiders Shopify generados desde `app/data/stores.json` (platform = "SHOPIFY").

`categoryPaths`: colección de la tienda (por ejemplo "teclados") -> slug de nuestra categoría.
"""

from app.spiders.listing_base import build_registry
from app.spiders.shopify.base import ShopifySpider

SPIDERS = build_registry("SHOPIFY", ShopifySpider, globals())
