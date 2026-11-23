"""Guarda ofertas en Firestore (PRECIO_JUSTO.md, secciones 9.3 y 11.3).

Por cada oferta:
- `storeProducts/{storeCode}__{externalId}`: estado actual de la publicación + asociación al producto.
- `storeProducts/{id}/history/{YYYY-MM}`: punto nuevo SOLO si cambió precio, disponibilidad o envío (RN-07).

Cuota gratuita: una publicación que no cambió NO se reescribe. Su verificación queda
registrada en `stores/{code}.lastCompleteRunAt` (una escritura por corrida completa): una
oferta con `missedRuns == 0` se considera verificada en esa fecha (ver `effective_checked_at`).

Al cerrar la corrida:
- Publicaciones que no aparecieron suman `missedRuns`; con 3 seguidas pasan a `GONE` (RN-09).
  Solo se hace en corridas completas (sin límite de páginas ni detención por la tienda).
- Se recalcula `products.summary` de los productos afectados.
- `scrapingJobs/{jobId}`: resumen de la ejecución.
"""

from __future__ import annotations

import os
from datetime import datetime, timezone

from firebase_admin import firestore
from google.cloud.firestore_v1.base_query import FieldFilter
from scrapy.exceptions import DropItem

from app.catalog import flatten_categories
from app.firebase_client import get_db
from app.matching.matcher import ProductMatcher
from app.models.offer import ScrapedOffer
from app.normalizers.text import word_tokens
from app.pipelines.base import CrawlerAwarePipeline
from app.postprocess.summary import refresh_summaries

TRACKED_FIELDS = ("currentPriceCents", "availability", "currentShippingCents")
# Si alguno de estos cambia, la publicación se reescribe (aunque el precio sea el mismo).
MATERIAL_FIELDS = TRACKED_FIELDS + (
    "title", "listPriceCents", "sellerName", "productUrl", "condition", "storeName", "brand",
    "model", "identifiers", "categoryHint", "productId", "matchStatus",
)
WRITE_BATCH_SIZE = 400
GONE_AFTER_MISSED_RUNS = 3


def build_store_product(offer: ScrapedOffer, store_name: str) -> dict:
    return {
        "storeCode": offer.store_code,
        "storeName": store_name,
        "externalProductId": offer.external_product_id,
        "title": offer.title,
        "titleTokens": word_tokens(offer.title, offer.brand, offer.model),
        "brand": offer.brand,
        "model": offer.model,
        "identifiers": offer.identifiers,
        "categoryHint": offer.category_hint,
        "productUrl": offer.product_url,
        "imageUrl": offer.image_url,
        "sellerName": offer.seller,
        "condition": offer.condition,
        "currentPriceCents": offer.price_cents,
        "listPriceCents": offer.list_price_cents,
        "currentShippingCents": offer.shipping_cents,
        "currency": offer.currency,
        "availability": offer.availability,
        "lastCheckedAt": offer.checked_at,
        "status": "ACTIVE",
        "missedRuns": 0,
        "updatedAt": firestore.SERVER_TIMESTAMP,
    }


def needs_write(previous: dict | None, current: dict) -> bool:
    """¿Hay que escribir la publicación? Solo si es nueva, volvió, o cambió algo material."""
    if previous is None or previous.get("status") != "ACTIVE" or previous.get("missedRuns", 0) != 0:
        return True
    return any(previous.get(f) != current.get(f) for f in MATERIAL_FIELDS)


def has_changed(previous: dict | None, current: dict) -> bool:
    if previous is None or previous.get("status") == "GONE":
        return True
    return any(previous.get(f) != current.get(f) for f in TRACKED_FIELDS)


class FirestorePipeline(CrawlerAwarePipeline):
    def __init__(self):
        self.db = None
        self.job_ref = None
        self.store_name = None
        self.matcher: ProductMatcher | None = None
        self.started: datetime | None = None
        self.seen: set[str] = set()
        self.affected_products: set[str] = set()
        self.existing: dict[str, dict] = {}
        self.batch = None
        self.pending_writes = 0
        self.write_all = False
        self.counters = {"found": 0, "saved": 0, "changed": 0, "matched": 0, "pending": 0, "unmatched": 0,
                         "gone": 0, "duplicates": 0, "written": 0, "unchanged": 0}

    def open_spider(self, spider=None):
        spider = self.spider
        self.db = get_db()
        store_code = spider.store_code
        store_doc = self.db.collection("stores").document(store_code).get()
        self.store_name = (store_doc.to_dict() or {}).get("name", store_code)
        self.matcher = ProductMatcher(self.db, {c["slug"] for c in flatten_categories()})
        # Una sola consulta con todas las publicaciones de la tienda (en vez de una lectura por oferta).
        query = self.db.collection("storeProducts").where(filter=FieldFilter("storeCode", "==", store_code))
        self.existing = {snap.id: snap.to_dict() or {} for snap in query.stream()}
        # En corridas parciales (max_pages) no se registra lastCompleteRunAt: se escriben todas.
        self.write_all = getattr(spider, "max_pages", None) is not None
        self.batch = self.db.batch()

        self.started = datetime.now(timezone.utc)
        job_id = f"{store_code}_{self.started.strftime('%Y%m%dT%H%M%SZ')}"
        self.job_ref = self.db.collection("scrapingJobs").document(job_id)
        self.job_ref.set({
            "storeCode": store_code,
            "jobType": os.getenv("JOB_TYPE", "MANUAL"),
            "status": "RUNNING",
            "startedAt": self.started,
            "runUrl": os.getenv("RUN_URL"),
        })

    def process_item(self, item: ScrapedOffer, spider=None):
        self.counters["found"] += 1
        if item.doc_id in self.seen:
            # El mismo SKU listado en dos categorías (por ejemplo, Laptops y Laptops Gamer).
            self.counters["duplicates"] += 1
            raise DropItem(f"duplicado en la corrida: {item.doc_id}")
        ref = self.db.collection("storeProducts").document(item.doc_id)
        previous = self.existing.get(item.doc_id)
        data = build_store_product(item, self.store_name)
        changed = has_changed(previous, data)

        decision = self.matcher.match(item, previous)
        if previous and previous.get("title") != item.title:
            self.matcher.refresh_owned_name(item, decision.product_id)
        data.update({
            "productId": decision.product_id,
            "matchStatus": decision.status,
            "matchScore": decision.score,
            "matchReason": decision.reason,
        })
        self.counters[{"MATCHED_AUTO": "matched", "MATCHED_MANUAL": "matched",
                       "PENDING_REVIEW": "pending"}.get(decision.status, "unmatched")] += 1

        if previous is None:
            data.update({
                "variantId": None,
                "previousPriceCents": None,
                "lastChangedAt": item.checked_at,
                "createdAt": firestore.SERVER_TIMESTAMP,
            })
        elif changed:
            if previous.get("currentPriceCents") != data["currentPriceCents"]:
                data["previousPriceCents"] = previous.get("currentPriceCents")
            data["lastChangedAt"] = item.checked_at

        self.seen.add(item.doc_id)
        self.counters["saved"] += 1
        if not (self.write_all or needs_write(previous, data)):
            # Sin cambios: no se escribe; la verificación la registra lastCompleteRunAt de la tienda.
            self.counters["unchanged"] += 1
            return item

        # Solo las asociaciones confirmadas aportan precio al producto (RN-06).
        if decision.status in ("MATCHED_AUTO", "MATCHED_MANUAL") and decision.product_id:
            self.affected_products.add(decision.product_id)
        if previous and previous.get("productId") and previous.get("productId") != decision.product_id:
            self.affected_products.add(previous["productId"])

        batch = self.batch
        if changed:
            self.counters["changed"] += 1
            month = item.checked_at.strftime("%Y-%m")
            point = {"t": item.checked_at, "p": item.price_cents, "a": item.availability, "s": item.shipping_cents}
            batch.set(
                ref.collection("history").document(month),
                {"month": month, "points": firestore.ArrayUnion([point]), "lastCheckedAt": item.checked_at},
                merge=True,
            )
        batch.set(ref, data, merge=True)
        self.counters["written"] += 1
        self.pending_writes += 2 if changed else 1
        if self.pending_writes >= WRITE_BATCH_SIZE:
            self._flush()
        return item

    def _flush(self) -> None:
        if self.pending_writes:
            self.batch.commit()
        self.batch, self.pending_writes = self.db.batch(), 0

    def _mark_missing(self, store_code: str) -> None:
        """RN-09: publicaciones que no aparecieron en esta corrida."""
        batch, pending = self.db.batch(), 0
        # Reutiliza las publicaciones leídas al inicio: no hace lecturas adicionales.
        for doc_id, data in self.existing.items():
            if doc_id in self.seen or data.get("status") != "ACTIVE":
                continue
            missed = int(data.get("missedRuns", 0)) + 1
            update = {"missedRuns": missed, "updatedAt": firestore.SERVER_TIMESTAMP}
            if missed >= GONE_AFTER_MISSED_RUNS:
                update["status"] = "GONE"
                self.counters["gone"] += 1
                if data.get("productId"):
                    self.affected_products.add(data["productId"])
            batch.update(self.db.collection("storeProducts").document(doc_id), update)
            pending += 1
            if pending >= 400:
                batch.commit()
                batch, pending = self.db.batch(), 0
        if pending:
            batch.commit()

    def close_spider(self, spider=None):
        spider = self.spider
        if getattr(spider, "not_due", False):
            self.job_ref.delete()  # no se hizo ninguna solicitud: no se registra corrida
            return
        stats = self.crawler.stats
        invalid = stats.get_value("offers/invalid", 0) + stats.get_value("offers/price_parse_failed", 0)
        errors = getattr(spider, "job_errors", [])
        stopped_early = getattr(spider, "stopped_early", False)
        complete_run = not stopped_early and getattr(spider, "max_pages", None) is None

        self._flush()
        if complete_run and self.counters["saved"] > 0:
            self._mark_missing(spider.store_code)
            # Verificación de todas las publicaciones vistas sin cambios (antes de los resúmenes).
            self.db.collection("stores").document(spider.store_code).set(
                {"lastCompleteRunAt": self.started}, merge=True
            )
        summaries = refresh_summaries(self.db, self.affected_products)

        if stopped_early:
            status = "PARTIAL" if self.counters["saved"] else "FAILED"
        else:
            status = "SUCCESS" if not errors else ("PARTIAL" if self.counters["saved"] else "FAILED")
        finished = datetime.now(timezone.utc)

        self.job_ref.update({
            "status": status,
            "finishedAt": finished,
            "productsFound": self.counters["found"] - self.counters["duplicates"] + invalid,
            "duplicatesSkipped": self.counters["duplicates"],
            "productsValidated": self.counters["saved"],
            "productsFailed": invalid,
            "pricesChanged": self.counters["changed"],
            "matched": self.counters["matched"],
            "pendingReview": self.counters["pending"],
            "unmatched": self.counters["unmatched"],
            "productsCreated": self.matcher.created_products if self.matcher else 0,
            "productsRenamed": self.matcher.renamed_products if self.matcher else 0,
            "written": self.counters["written"],
            "unchanged": self.counters["unchanged"],
            "markedGone": self.counters["gone"],
            "summariesUpdated": summaries,
            "completeRun": complete_run,
            "alertsTriggered": 0,  # Se implementa en el sprint 8
            "errors": errors,
        })
        self.db.collection("stores").document(spider.store_code).set(
            {"lastRunAt": finished, "lastRunStatus": status}, merge=True
        )
        spider.logger.info("Job %s terminado: %s %s", self.job_ref.id, status, self.counters)
