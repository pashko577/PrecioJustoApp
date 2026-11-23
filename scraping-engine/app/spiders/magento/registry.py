"""Spiders Magento generados desde `app/data/stores.json` (platform = "MAGENTO").

Cada tienda define su evaluación (sección 7.7) y `categoryPaths`: ruta del listado
(por ejemplo "/tecnologia/computacion/laptops.html") -> slug de nuestra categoría.
"""

from app.spiders.listing_base import build_registry
from app.spiders.magento.base import MagentoSpider

SPIDERS = build_registry("MAGENTO", MagentoSpider, globals())
