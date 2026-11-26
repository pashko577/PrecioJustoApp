"""Spiders de tiendas de cómputo generados desde `app/data/stores.json`.

- platform "CGS": CGS Computer (`categoryPaths`: "p=OQ==&cat=Procesadores" -> slug).
- platform "BANANASTORE": Banana Store (`categoryPaths`: "memoria-ram" -> slug).
- platform "FABRITEC": Fabritec (`categoryPaths`: "9/30" = categoría/subcategoría -> slug).
"""

from app.spiders.listing_base import build_registry
from app.spiders.tiendas_pc.bananastore import BananaStoreSpider
from app.spiders.tiendas_pc.cgs import CgsSpider
from app.spiders.tiendas_pc.fabritec import FabritecSpider

SPIDERS = {
    **build_registry("CGS", CgsSpider, globals()),
    **build_registry("BANANASTORE", BananaStoreSpider, globals()),
    **build_registry("FABRITEC", FabritecSpider, globals()),
}
