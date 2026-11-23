"""Spiders PrestaShop generados desde `app/data/stores.json` (platform = "PRESTASHOP").

`categoryPaths`: ruta del listado (por ejemplo "/3-laptops") -> slug de nuestra categoría.
"""

from app.spiders.listing_base import build_registry
from app.spiders.prestashop.base import PrestaShopSpider

SPIDERS = build_registry("PRESTASHOP", PrestaShopSpider, globals())
