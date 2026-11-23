"""Resumen de precios de cada producto (`products/{id}.summary`) — RN-01, RN-02, RN-04.

Se recalcula al terminar cada corrida, solo para los productos afectados.
"""

from __future__ import annotations

from datetime import datetime, timedelta, timezone

from firebase_admin import firestore
from google.cloud.firestore_v1.base_query import FieldFilter

from app.catalog import NO_PRICE_SORT_VALUE

DEFAULT_FRESHNESS_MINUTES = 12 * 60
# Estados de asociación que se muestran como precio del producto (la app usa la misma lista).
SHOWN_MATCH_STATUSES = ("MATCHED_AUTO", "MATCHED_MANUAL")


def effective_checked_at(offer: dict, store: dict | None) -> datetime | None:
    """Última verificación real de una oferta.

    Las ofertas sin cambios no se reescriben: si apareció en la última corrida completa de su
    tienda (`missedRuns == 0`), su verificación es `stores.lastCompleteRunAt`.
    """
    checked = offer.get("lastCheckedAt")
    run = (store or {}).get("lastCompleteRunAt")
    if run is not None and offer.get("missedRuns", 0) == 0 and offer.get("status", "ACTIVE") == "ACTIVE":
        return max(checked, run) if checked else run
    return checked


def compute_summary(offers: list[dict], stores: dict[str, dict], now: datetime | None = None) -> dict:
    """Calcula el resumen a partir de los documentos `storeProducts` de un producto.

    `stores`: código de tienda -> `{freshnessMinutes, lastCompleteRunAt}`.
    Precio mínimo: solo ofertas activas, vigentes, disponibles y en PEN.
    """
    now = now or datetime.now(timezone.utc)
    # Solo asociaciones confirmadas: una publicación en revisión conserva el producto como
    # SUGERENCIA y no debe aparecer como precio de ese producto hasta que alguien la apruebe.
    active = [o for o in offers if o.get("status", "ACTIVE") == "ACTIVE"
              and o.get("matchStatus", "MATCHED_AUTO") in SHOWN_MATCH_STATUSES]
    verified = []
    checks = []
    for o in active:
        store = stores.get(o.get("storeCode")) or {}
        checked = effective_checked_at(o, store)
        if checked:
            checks.append(checked)
        freshness = store.get("freshnessMinutes", DEFAULT_FRESHNESS_MINUTES)
        fresh = checked is not None and now - checked <= timedelta(minutes=freshness)
        if fresh and o.get("availability") == "AVAILABLE" and o.get("currency", "PEN") == "PEN":
            verified.append(o)

    best = min(verified, key=lambda o: o["currentPriceCents"]) if verified else None
    prices = [o["currentPriceCents"] for o in active if o.get("currentPriceCents")]
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


def store_info(db) -> dict[str, dict]:
    return {snap.id: snap.to_dict() or {} for snap in db.collection("stores").stream()}


def refresh_summaries(db, product_ids: set[str]) -> int:
    """Recalcula y guarda el resumen de los productos indicados. Devuelve cuántos actualizó."""
    if not product_ids:
        return 0
    stores = store_info(db)
    batch, pending, updated = db.batch(), 0, 0
    for pid in sorted(product_ids):
        offers = [
            s.to_dict() for s in db.collection("storeProducts").where(filter=FieldFilter("productId", "==", pid)).stream()
        ]
        # set+merge: no falla si el producto ya no existe (un update haría fallar todo el lote).
        batch.set(db.collection("products").document(pid), {
            "summary": compute_summary(offers, stores),
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
