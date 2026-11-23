"""Guarda ofertas en Firestore (PRECIO_JUSTO.md, secciones 9.3 y 11.3).

Por cada oferta:
- `storeProducts/{storeCode}__{externalId}`: estado actual de la publicación + asociación al producto.
- `storeProducts/{id}/history/{YYYY-MM}`: punto nuevo SOLO si cambió precio, disponibilidad o envío (RN-07).

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
        self.counters = {"found": 0, "saved": 0, "changed": 0, "matched": 0, "pending": 0, "unmatched": 0,
                         "gone": 0, "duplicates": 0}

    def open_spider(self, spider=None):
        spider = self.spider
        self.db = get_db()
        store_code = spider.store_code
        store_doc = self.db.collection("stores").document(store_code).get()
        self.store_name = (store_doc.to_dict() or {}).get("name", store_code)
        self.matcher = ProductMatcher(self.db, {c["slug"] for c in flatten_categories()})

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
        snapshot = ref.get()
        previous = snapshot.to_dict() if snapshot.exists else None
        data = build_store_product(item, self.store_name)
        changed = has_changed(previous, data)

        decision = self.matcher.match(item, previous)
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

        # Solo las asociaciones confirmadas aportan precio al producto (RN-06).
        if decision.status in ("MATCHED_AUTO", "MATCHED_MANUAL") and decision.product_id:
            self.affected_products.add(decision.product_id)
        if previous and previous.get("productId") and previous.get("productId") != decision.product_id:
            self.affected_products.add(previous["productId"])

        batch = self.db.batch()
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
        batch.commit()
        self.seen.add(item.doc_id)
        self.counters["saved"] += 1
        return item

    def _mark_missing(self, store_code: str) -> None:
        """RN-09: publicaciones que no aparecieron en esta corrida."""
        batch, pending = self.db.batch(), 0
        query = (self.db.collection("storeProducts")
                 .where(filter=FieldFilter("storeCode", "==", store_code))
                 .where(filter=FieldFilter("status", "==", "ACTIVE")))
        for snap in query.stream():
            if snap.id in self.seen:
                continue
            data = snap.to_dict() or {}
            missed = int(data.get("missedRuns", 0)) + 1
            update = {"missedRuns": missed, "updatedAt": firestore.SERVER_TIMESTAMP}
            if missed >= GONE_AFTER_MISSED_RUNS:
                update["status"] = "GONE"
                self.counters["gone"] += 1
                if data.get("productId"):
                    self.affected_products.add(data["productId"])
            batch.update(snap.reference, update)
            pending += 1
            if pending >= 400:
                batch.commit()
                batch, pending = self.db.batch(), 0
        if pending:
            batch.commit()

    def close_spider(self, spider=None):
        spider = self.spider
        stats = self.crawler.stats
        invalid = stats.get_value("offers/invalid", 0) + stats.get_value("offers/price_parse_failed", 0)
        errors = getattr(spider, "job_errors", [])
        stopped_early = getattr(spider, "stopped_early", False)
        complete_run = not stopped_early and getattr(spider, "max_pages", None) is None

        if complete_run and self.counters["saved"] > 0:
            self._mark_missing(spider.store_code)
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
