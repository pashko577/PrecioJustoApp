"""Spiders WooCommerce generados desde `app/data/stores.json` (platform = "WOOCOMMERCE").

`categoryPaths`: id de la categoría de WooCommerce (por ejemplo "138") -> slug de nuestra categoría.
"""

from app.spiders.listing_base import build_registry
from app.spiders.woocommerce.base import WooCommerceSpider

SPIDERS = build_registry("WOOCOMMERCE", WooCommerceSpider, globals())
