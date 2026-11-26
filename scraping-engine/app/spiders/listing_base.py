"""Base común para extractores de listados (Magento, PrestaShop, Memory Kings, Shopify, WooCommerce...).

Cada plataforma define cómo se arma la URL de una página (`page_url`) y cómo se lee un
listado (`parse_body`). Esta base aporta las reglas de extracción responsable
(COMPRA_MEJOR.md, 7.7): una solicitud a la vez con pausa, frecuencia por tienda, y se
DETIENE ante HTTP 403/429/503 o un desafío anti-bots (no lo evade).

Los spiders se generan desde `app/data/stores.json` con `build_registry`.
"""

from __future__ import annotations

import json
import os
import re
from pathlib import Path
from urllib.parse import urlparse

import scrapy
from scrapy.exceptions import CloseSpider

from app.models.offer import ScrapedOffer
from app.pipelines.job_errors import record_error
from app.spiders.vtex.base import is_due

# 426: Efe (Fastly) lo responde a servidores de centros de datos (GitHub Actions): es un bloqueo.
STOP_STATUSES = (403, 426, 429, 503)
MAX_PAGES_PER_CATEGORY = 60  # tope de seguridad
# Alcance normal por categoría (cuota gratuita de Firestore); configurable por tienda.
DEFAULT_SCOPE_PAGES = 6
STORES_FILE = Path(__file__).resolve().parents[1] / "data" / "stores.json"

# Página de desafío de Cloudflare. No confundir con el script pasivo
# "/cdn-cgi/challenge-platform/scripts/jsd/main.js" que Cloudflare agrega a páginas normales.
CHALLENGE_RE = re.compile(r"cf-chl|challenge-platform/h/|<title>\s*Just a moment|Attention Required", re.I)
REFURBISHED_RE = re.compile(r"reacondicionad|refurbished|open box|seminuevo|exhibici[oó]n", re.I)


def is_challenge(body: str) -> bool:
    return bool(CHALLENGE_RE.search(body[:20000]))


class ListingSpider(scrapy.Spider):
    """Base: cada tienda define `store_code`, `base_url` y `categories` (ruta -> slug)."""

    store_code: str = ""
    base_url: str = ""
    categories: dict[str, str] = {}
    scope_pages: int = DEFAULT_SCOPE_PAGES
    store_config: dict = {}  # entrada de stores.json (opciones propias de cada plataforma)
    # Listados sin total (APIs JSON): se pide la página siguiente mientras venga llena.
    full_page_size: int | None = None

    handle_httpstatus_list = list(STOP_STATUSES)
    custom_settings = {
        "DOWNLOAD_DELAY": 6,
        "CONCURRENT_REQUESTS_PER_DOMAIN": 1,
        "RETRY_HTTP_CODES": [500, 502, 504, 522, 524, 408],
    }

    def __init__(self, *args, max_pages: int | str | None = None, **kwargs):
        super().__init__(*args, **kwargs)
        self.max_pages = int(max_pages) if max_pages else None
        self.job_errors: list[dict] = []
        self.stopped_early = False
        self.not_due = False
        self.seen_ids: set[str] = set()

    # ---- Puntos de extensión por plataforma ----

    def page_url(self, path: str, page: int) -> str:
        raise NotImplementedError

    def parse_body(self, body: str, slug: str) -> tuple[list[ScrapedOffer], list[str], int | None]:
        """Devuelve `(ofertas, avisos, total_de_productos_o_None)`."""
        raise NotImplementedError

    # ---- Lógica común ----

    def make_request(self, path: str, slug: str, page: int) -> scrapy.Request:
        return scrapy.Request(self.page_url(path, page), callback=self.parse_page,
                              cb_kwargs={"path": path, "slug": slug, "page": page})

    def _store_is_due(self) -> bool:
        if os.getenv("JOB_TYPE") != "SCHEDULED":
            return True
        from app.firebase_client import get_db

        snap = get_db().collection("stores").document(self.store_code).get()
        return is_due(snap.to_dict() if snap.exists else None)

    async def start(self):
        if getattr(self, "not_due", False):  # el pipeline decidió no correr (presupuesto diario)
            return
        if not self._store_is_due():
            self.not_due = True
            self.logger.info("%s: todavía no toca según su frecuencia; no se hacen solicitudes.", self.store_code)
            return
        for path, slug in self.categories.items():
            yield self.make_request(path, slug, 1)

    def stop_if_blocked(self, response, where: str) -> str:
        """Texto de la respuesta; ante 403/426/429/503 o un desafío anti-bots detiene la corrida."""
        body = response.text if hasattr(response, "text") else ""
        if response.status in STOP_STATUSES or is_challenge(body):
            self.stopped_early = True
            message = f"HTTP {response.status} o desafío anti-bots en {where}: se suspende la corrida (no se evade)."
            record_error(self, "ERROR", message, response.url)
            raise CloseSpider(f"blocked_{response.status}")
        return body

    def emit(self, offers: list[ScrapedOffer], warnings: list[str]):
        for warning in warnings:
            self.crawler.stats.inc_value("offers/skipped")
            self.logger.debug(warning)
        for offer in offers:
            # Un mismo producto puede aparecer en varios listados: se envía una sola vez.
            if offer.external_product_id in self.seen_ids:
                continue
            self.seen_ids.add(offer.external_product_id)
            yield offer

    def parse_page(self, response, path: str, slug: str, page: int):
        body = self.stop_if_blocked(response, path)
        offers, warnings, total = self.parse_body(body, slug)
        yield from self.emit(offers, warnings)

        per_page = max(len(offers) + len(warnings), 1)
        within_limit = page < min(self.max_pages or self.scope_pages, MAX_PAGES_PER_CATEGORY)
        if total is None and self.full_page_size:
            more = per_page >= self.full_page_size
        else:
            more = bool(total) and page * per_page < total
        if offers and more and within_limit:
            yield self.make_request(path, slug, page + 1)


def store_configs(platform: str, path: Path = STORES_FILE) -> list[dict]:
    return [s for s in json.loads(path.read_text("utf-8")) if s.get("platform") == platform and s.get("spider")]


def build_spider_class(store: dict, base: type[ListingSpider], module: str) -> type[ListingSpider]:
    class_name = "".join(part.capitalize() for part in store["spider"].split("_")) + "Spider"
    settings = dict(base.custom_settings)
    if store.get("downloadDelay"):
        # robots.txt con Crawl-delay mayor que la pausa por defecto: se respeta el de la tienda.
        settings["DOWNLOAD_DELAY"] = max(settings.get("DOWNLOAD_DELAY", 0), store["downloadDelay"])
    return type(class_name, (base,), {
        "custom_settings": settings,
        "__module__": module,
        "__doc__": f"{store['name']} ({store['baseUrl']}) — generado desde stores.json.",
        "name": store["spider"],
        "store_code": store["code"],
        "base_url": store["baseUrl"].rstrip("/"),
        "allowed_domains": [urlparse(store["baseUrl"]).netloc],
        "categories": dict(store.get("categoryPaths") or {}),
        "scope_pages": int(store.get("maxPagesPerCategory") or DEFAULT_SCOPE_PAGES),
        "store_config": store,
    })


def build_registry(platform: str, base: type[ListingSpider], module_globals: dict) -> dict[str, type[ListingSpider]]:
    """Crea un spider por tienda de la plataforma y lo publica en el módulo (Scrapy los busca ahí)."""
    spiders: dict[str, type[ListingSpider]] = {}
    for store in store_configs(platform):
        cls = build_spider_class(store, base, module_globals["__name__"])
        spiders[cls.name] = cls
        module_globals[cls.__name__] = cls
    return spiders
