"""Spiders VTEX generados desde `app/data/stores.json`.

Agregar una tienda VTEX es solo configuración: su evaluación (sección 7.7) y su mapa de
categorías (`vtexCategories`: id de categoría VTEX -> slug de nuestra categoría).
Se genera un spider por tienda; el workflow solo ejecuta las que tienen `scrapingEnabled`.
"""

from __future__ import annotations

import json
from pathlib import Path
from urllib.parse import urlparse

from app.spiders.vtex.base import VtexSpider

STORES_FILE = Path(__file__).resolve().parents[2] / "data" / "stores.json"


def vtex_store_configs(path: Path = STORES_FILE) -> list[dict]:
    return [s for s in json.loads(path.read_text("utf-8")) if s.get("platform") == "VTEX" and s.get("spider")]


def build_spider_class(store: dict) -> type[VtexSpider]:
    class_name = "".join(part.capitalize() for part in store["spider"].split("_")) + "Spider"
    return type(class_name, (VtexSpider,), {
        "__module__": __name__,
        "__doc__": f"{store['name']} ({store['baseUrl']}) — generado desde stores.json.",
        "name": store["spider"],
        "store_code": store["code"],
        "base_url": store["baseUrl"].rstrip("/"),
        "allowed_domains": [urlparse(store["baseUrl"]).netloc],
        "categories": dict(store.get("vtexCategories") or {}),
        "internal_sellers": tuple(store.get("vtexInternalSellers") or ()),
    })


SPIDERS: dict[str, type[VtexSpider]] = {}
for _store in vtex_store_configs():
    _cls = build_spider_class(_store)
    SPIDERS[_cls.name] = _cls
    globals()[_cls.__name__] = _cls  # Scrapy descubre los spiders por los atributos del módulo

# Variables temporales fuera del módulo: Scrapy contaría la última clase dos veces.
del _store, _cls
