"""Resumen de precios de cada producto (`products/{id}.summary`) — RN-01, RN-02, RN-04.

Se recalcula al terminar cada corrida, solo para los productos afectados.
"""

from __future__ import annotations

from datetime import datetime, timedelta, timezone

from firebase_admin import firestore
from google.cloud.firestore_v1.base_query import FieldFilter

from app.catalog import NO_PRICE_SORT_VALUE

DEFAULT_FRESHNESS_MINUTES = 12 * 60
# Una bajada se anuncia («Bajó X %») solo durante estos días desde que la observamos.
PRICE_DROP_WINDOW_DAYS = 7
# Bajadas mayores suelen ser errores de lectura de la tienda: no se anuncian.
MAX_PLAUSIBLE_DROP_PERCENT = 80
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


def price_drop(best: dict | None, verified: list[dict], now: datetime) -> dict:
    """Bajada reciente del mejor precio del producto, según precios OBSERVADOS por nosotros.

    Nunca usa el precio «normal» que publica la tienda (`listPriceCents`). Compara el precio
    actual de la oferta más barata con el mejor precio que el producto tenía antes de ese cambio:
    el anterior de esa oferta o, si era menor, el actual de otra tienda vigente.
    """
    none = {"priceDropFromCents": None, "priceDropPercent": None, "priceDroppedAt": None}
    if not best:
        return none
    previous, changed_at = best.get("previousPriceCents"), best.get("lastChangedAt")
    current = best["currentPriceCents"]
    if not previous or not changed_at or previous <= current:
        return none
    if now - changed_at > timedelta(days=PRICE_DROP_WINDOW_DAYS):
        return none
    others = [o["currentPriceCents"] for o in verified if o is not best]
    reference = min([previous, *others])
    if reference <= current:
        return none
    percent = round((reference - current) * 100 / reference)
    if percent < 1 or percent > MAX_PLAUSIBLE_DROP_PERCENT:
        return none
    return {"priceDropFromCents": reference, "priceDropPercent": percent, "priceDroppedAt": changed_at}


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
        # Tiendas distintas: en un marketplace varios vendedores publican el mismo producto.
        "storeCount": len({o.get("storeCode") for o in active}),
        "verifiedOfferCount": len(verified),
        "lastCheckedAt": max(checks) if checks else None,
        # Campos siempre presentes (también en None): el guardado con merge no debe dejar
        # una bajada antigua colgada en el resumen.
        **price_drop(best, verified, now),
    }


def allowed_image_stores(stores: dict[str, dict]) -> set[str]:
    """Tiendas cuyas fotos se pueden mostrar (`showImages`: permiso o licencia de la tienda)."""
    return {code for code, s in stores.items() if s.get("showImages")}


def product_image(offers: list[dict], allowed_stores: set[str]) -> dict | None:
    """Foto del producto: la de su oferta confirmada más antigua, de una tienda que lo permite.

    Devuelve `{"imageUrl", "imageStoreCode"}`. Estable entre corridas (no cambia de tienda en
    tienda), sin lecturas extra. Las fotos son de las tiendas o de las marcas (derecho de autor,
    D. Leg. 822): sin permiso de la tienda no se muestran.
    """
    with_image = [o for o in offers if o.get("imageUrl") and o.get("status", "ACTIVE") == "ACTIVE"
                  and o.get("storeCode") in allowed_stores
                  and o.get("matchStatus", "MATCHED_AUTO") in SHOWN_MATCH_STATUSES]
    if not with_image:
        return None
    far_future = datetime.max.replace(tzinfo=timezone.utc)
    oldest = min(with_image, key=lambda o: (o.get("createdAt") or far_future, o.get("storeCode") or ""))
    return {"imageUrl": oldest["imageUrl"], "imageStoreCode": oldest.get("storeCode")}


def store_info(db) -> dict[str, dict]:
    return {snap.id: snap.to_dict() or {} for snap in db.collection("stores").stream()}


def refresh_summaries(db, product_ids: set[str]) -> int:
    """Recalcula y guarda el resumen de los productos indicados. Devuelve cuántos actualizó."""
    if not product_ids:
        return 0
    stores = store_info(db)
    allowed = allowed_image_stores(stores)
    batch, pending, updated = db.batch(), 0, 0
    for pid in sorted(product_ids):
        offers = [
            s.to_dict() for s in db.collection("storeProducts").where(filter=FieldFilter("productId", "==", pid)).stream()
        ]
        data = {"summary": compute_summary(offers, stores), "updatedAt": firestore.SERVER_TIMESTAMP}
        # Sin foto permitida se borra la que tuviera (por ejemplo, si la tienda retiró el permiso).
        data.update(product_image(offers, allowed)
                    or {"imageUrl": firestore.DELETE_FIELD, "imageStoreCode": firestore.DELETE_FIELD})
        # set+merge: no falla si el producto ya no existe (un update haría fallar todo el lote).
        batch.set(db.collection("products").document(pid), data, merge=True)
        pending += 1
        updated += 1
        if pending >= 400:
            batch.commit()
            batch, pending = db.batch(), 0
    if pending:
        batch.commit()
    return updated
