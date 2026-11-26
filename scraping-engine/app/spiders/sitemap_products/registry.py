"""Spiders «mapa del sitio + ficha» generados desde `app/data/stores.json` (platform = "SITEMAP_JSONLD").

`categoryPaths`: expresión regular sobre el nombre de la ficha (por ejemplo "^procesador") -> slug.
"""

from app.spiders.listing_base import build_registry
from app.spiders.sitemap_products.base import SitemapProductsSpider

SPIDERS = build_registry("SITEMAP_JSONLD", SitemapProductsSpider, globals())
