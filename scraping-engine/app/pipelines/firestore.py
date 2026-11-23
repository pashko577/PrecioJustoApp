"""Guarda ofertas en Firestore (PRECIO_JUSTO.md, secciones 9.3 y 11.3).

- `storeProducts/{storeCode}__{externalId}`: estado actual de la publicación.
- `storeProducts/{id}/history/{YYYY-MM}`: se agrega un punto SOLO si cambió precio,
  disponibilidad o envío (RN-07), para ahorrar escrituras.
- `scrapingJobs/{jobId}`: resumen de la ejecución.
"""

from __future__ import annotations

import os
from datetime import datetime, timezone

from firebase_admin import firestore

from app.firebase_client import get_db
from app.models.offer import ScrapedOffer
from app.pipelines.base import CrawlerAwarePipeline
from app.normalizers.text import word_tokens

TRACKED_FIELDS = ("currentPriceCents", "availability", "currentShippingCents")


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
        "productUrl": offer.product_url,
        "imageUrl": offer.image_url,
        "sellerName": offer.seller,
        "condition": offer.condition,
        "currentPriceCents": offer.price_cents,
        "currentShippingCents": offer.shipping_cents,
        "currency": offer.currency,
        "availability": offer.availability,
        "lastCheckedAt": offer.checked_at,
        "status": "ACTIVE",
        "missedRuns": 0,
        "updatedAt": firestore.SERVER_TIMESTAMP,
    }


def has_changed(previous: dict | None, current: dict) -> bool:
    if previous is None:
        return True
    return any(previous.get(f) != current.get(f) for f in TRACKED_FIELDS)


class FirestorePipeline(CrawlerAwarePipeline):
    def __init__(self):
        self.db = None
        self.job_ref = None
        self.store_name = None
        self.counters = {"found": 0, "saved": 0, "changed": 0}

    def open_spider(self, spider=None):
        spider = self.spider
        self.db = get_db()
        store_code = spider.store_code
        store_doc = self.db.collection("stores").document(store_code).get()
        self.store_name = (store_doc.to_dict() or {}).get("name", store_code)

        started = datetime.now(timezone.utc)
        job_id = f"{store_code}_{started.strftime('%Y%m%dT%H%M%SZ')}"
        self.job_ref = self.db.collection("scrapingJobs").document(job_id)
        self.job_ref.set({
            "storeCode": store_code,
            "jobType": os.getenv("JOB_TYPE", "MANUAL"),
            "status": "RUNNING",
            "startedAt": started,
            "runUrl": os.getenv("RUN_URL"),
        })

    def process_item(self, item: ScrapedOffer, spider=None):
        self.counters["found"] += 1
        ref = self.db.collection("storeProducts").document(item.doc_id)
        snapshot = ref.get()
        previous = snapshot.to_dict() if snapshot.exists else None
        data = build_store_product(item, self.store_name)
        changed = has_changed(previous, data)

        batch = self.db.batch()
        if previous is None:
            data.update({
                "productId": None,
                "variantId": None,
                "matchStatus": "UNMATCHED",
                "matchScore": None,
                "previousPriceCents": None,
                "lastChangedAt": item.checked_at,
                "createdAt": firestore.SERVER_TIMESTAMP,
            })
        elif changed:
            if previous.get("currentPriceCents") != data["currentPriceCents"]:
                data["previousPriceCents"] = previous.get("currentPriceCents")
            data["lastChangedAt"] = item.checked_at

        if changed:
            self.counters["changed"] += 1
            month = item.checked_at.strftime("%Y-%m")
            point = {
                "t": item.checked_at,
                "p": item.price_cents,
                "a": item.availability,
                "s": item.shipping_cents,
            }
            batch.set(
                ref.collection("history").document(month),
                {"month": month, "points": firestore.ArrayUnion([point]), "lastCheckedAt": item.checked_at},
                merge=True,
            )

        batch.set(ref, data, merge=True)
        batch.commit()
        self.counters["saved"] += 1
        return item

    def close_spider(self, spider=None):
        spider = self.spider
        stats = self.crawler.stats
        invalid = stats.get_value("offers/invalid", 0) + stats.get_value("offers/price_parse_failed", 0)
        errors = getattr(spider, "job_errors", [])
        status = "SUCCESS" if not errors else ("PARTIAL" if self.counters["saved"] else "FAILED")
        finished = datetime.now(timezone.utc)

        self.job_ref.update({
            "status": status,
            "finishedAt": finished,
            "productsFound": self.counters["found"] + invalid,
            "productsValidated": self.counters["saved"],
            "productsFailed": invalid,
            "pricesChanged": self.counters["changed"],
            "alertsTriggered": 0,  # Se implementa en el sprint 8
            "errors": errors,
        })
        self.db.collection("stores").document(spider.store_code).set(
            {"lastRunAt": finished, "lastRunStatus": status}, merge=True
        )
        spider.logger.info("Job %s terminado: %s %s", self.job_ref.id, status, self.counters)
