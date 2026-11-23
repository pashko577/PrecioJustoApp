"""Spider de Memory Kings generado desde `app/data/stores.json` (platform = "MEMORYKINGS").

`categoryPaths`: listado (por ejemplo "/listados/258/laptops-core-i5") -> slug de nuestra categoría.
"""

from app.spiders.listing_base import build_registry
from app.spiders.memorykings.base import MemoryKingsSpider

SPIDERS = build_registry("MEMORYKINGS", MemoryKingsSpider, globals())
