"""Resumen de precios de cada producto (`products/{id}.summary`) — RN-01, RN-02, RN-04.

Se recalcula al terminar cada corrida, solo para los productos afectados.
"""

from __future__ import annotations

from datetime import datetime, timedelta, timezone

from firebase_admin import firestore
from google.cloud.firestore_v1.base_query import FieldFilter

from app.catalog import NO_PRICE_SORT_VALUE

DEFAULT_FRESHNESS_MINUTES = 12 * 60


def compute_summary(offers: list[dict], freshness_by_store: dict[str, int], now: datetime | None = None) -> dict:
    """Calcula el resumen a partir de los documentos `storeProducts` de un producto.

    Precio mínimo: solo ofertas activas, vigentes, disponibles y en PEN.
    """
    now = now or datetime.now(timezone.utc)
    active = [o for o in offers if o.get("status", "ACTIVE") == "ACTIVE"]
    verified = []
    for o in active:
        checked = o.get("lastCheckedAt")
        freshness = freshness_by_store.get(o.get("storeCode"), DEFAULT_FRESHNESS_MINUTES)
        fresh = checked is not None and now - checked <= timedelta(minutes=freshness)
        if fresh and o.get("availability") == "AVAILABLE" and o.get("currency", "PEN") == "PEN":
            verified.append(o)

    best = min(verified, key=lambda o: o["currentPriceCents"]) if verified else None
    prices = [o["currentPriceCents"] for o in active if o.get("currentPriceCents")]
    checks = [o["lastCheckedAt"] for o in active if o.get("lastCheckedAt")]
    return {
        "currency": "PEN",
        "minPriceCents": best["currentPriceCents"] if best else None,
        "minPriceStoreCode": best.get("storeCode") if best else None,
        "maxPriceCents": max(prices) if prices else None,
        "sortPriceCents": best["currentPriceCents"] if best else NO_PRICE_SORT_VALUE,
        "offerCount": len(active),
        "verifiedOfferCount": len(verified),
        "lastCheckedAt": max(checks) if checks else None,
    }


def store_freshness(db) -> dict[str, int]:
    return {
        snap.id: (snap.to_dict() or {}).get("freshnessMinutes", DEFAULT_FRESHNESS_MINUTES)
        for snap in db.collection("stores").stream()
    }


def refresh_summaries(db, product_ids: set[str]) -> int:
    """Recalcula y guarda el resumen de los productos indicados. Devuelve cuántos actualizó."""
    if not product_ids:
        return 0
    freshness = store_freshness(db)
    batch, pending, updated = db.batch(), 0, 0
    for pid in sorted(product_ids):
        offers = [
            s.to_dict() for s in db.collection("storeProducts").where(filter=FieldFilter("productId", "==", pid)).stream()
        ]
        # set+merge: no falla si el producto ya no existe (un update haría fallar todo el lote).
        batch.set(db.collection("products").document(pid), {
            "summary": compute_summary(offers, freshness),
            "updatedAt": firestore.SERVER_TIMESTAMP,
        }, merge=True)
        pending += 1
        updated += 1
        if pending >= 400:
            batch.commit()
            batch, pending = db.batch(), 0
    if pending:
        batch.commit()
    return updated
