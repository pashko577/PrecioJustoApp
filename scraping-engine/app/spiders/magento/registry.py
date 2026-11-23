"""Spiders Magento generados desde `app/data/stores.json` (platform = "MAGENTO").

Cada tienda define su evaluación (sección 7.7) y `categoryPaths`: ruta del listado
(por ejemplo "/tecnologia/computacion/laptops.html") -> slug de nuestra categoría.
"""

from __future__ import annotations

import json
from pathlib import Path
from urllib.parse import urlparse

from app.spiders.magento.base import MagentoSpider

STORES_FILE = Path(__file__).resolve().parents[2] / "data" / "stores.json"


def magento_store_configs(path: Path = STORES_FILE) -> list[dict]:
    return [s for s in json.loads(path.read_text("utf-8")) if s.get("platform") == "MAGENTO" and s.get("spider")]


def build_spider_class(store: dict) -> type[MagentoSpider]:
    class_name = "".join(part.capitalize() for part in store["spider"].split("_")) + "Spider"
    return type(class_name, (MagentoSpider,), {
        "__module__": __name__,
        "__doc__": f"{store['name']} ({store['baseUrl']}) — generado desde stores.json.",
        "name": store["spider"],
        "store_code": store["code"],
        "base_url": store["baseUrl"].rstrip("/"),
        "allowed_domains": [urlparse(store["baseUrl"]).netloc],
        "categories": dict(store.get("categoryPaths") or {}),
    })


SPIDERS: dict[str, type[MagentoSpider]] = {}
for _store in magento_store_configs():
    _cls = build_spider_class(_store)
    SPIDERS[_cls.name] = _cls
    globals()[_cls.__name__] = _cls

# Variables temporales fuera del módulo: Scrapy contaría la última clase dos veces.
if SPIDERS:
    del _store, _cls
