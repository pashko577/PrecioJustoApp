"""Evaluación de alertas de precio y notificaciones (RF-06, RF-12, RN-08).

Se ejecuta al cerrar cada corrida, para:
- las alertas ACTIVAS de los productos cuyo resumen cambió en la corrida, y
- las alertas ACTIVAS nunca evaluadas (`evaluatedAt == null`), por ejemplo recién creadas.

Regla RN-08 (la alerta sigue ACTIVA después de avisar, para poder volver a avisar):
- mejor precio vigente <= objetivo y nunca avisó          -> AVISAR
- mejor precio vigente <  último precio avisado           -> AVISAR (bajó todavía más)
- mejor precio vigente  > objetivo y ya había avisado     -> REARMAR (podrá avisar de nuevo)
- en otro caso                                            -> nada
"""

from __future__ import annotations

import logging
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone

from firebase_admin import firestore
from google.cloud.firestore_v1.base_query import FieldFilter

from app.firebase_client import using_emulator

logger = logging.getLogger(__name__)

NOTIFY, REARM, NOTHING = "NOTIFY", "REARM", "NOTHING"


def decide_alert(target_cents: int, last_notified_cents: int | None, best_cents: int | None) -> str:
    """Decisión para una alerta AT_OR_BELOW (función pura, ver docstring del módulo)."""
    if best_cents is None:
        return NOTHING  # sin precio vigente y disponible: no se decide nada
    if best_cents <= target_cents:
        if last_notified_cents is None or best_cents < last_notified_cents:
            return NOTIFY
        return NOTHING
    return REARM if last_notified_cents is not None else NOTHING


def fresh_best_price(summary: dict, store: dict | None, now: datetime) -> int | None:
    """Mejor precio del resumen SOLO si sigue vigente (RN-01): nunca se avisa con un precio vencido."""
    best = summary.get("minPriceCents")
    if best is None:
        return None
    checked = summary.get("lastCheckedAt")
    run = (store or {}).get("lastCompleteRunAt")
    if run is not None and (checked is None or run > checked):
        checked = run
    freshness = timedelta(minutes=int((store or {}).get("freshnessMinutes") or 720))
    return best if checked is not None and now - checked <= freshness else None


def format_soles(cents: int) -> str:
    units, decimals = divmod(cents, 100)
    return f"S/ {units:,}.{decimals:02d}"


def alert_message(product_name: str, best_cents: int, store_name: str, target_cents: int) -> tuple[str, str]:
    title = "¡Bajó de precio!"
    body = (f"{product_name} está a {format_soles(best_cents)} en {store_name} "
            f"(tu alerta: {format_soles(target_cents)}).")
    return title, body


def wants_price_alert_push(user: dict | None) -> bool:
    prefs = (user or {}).get("notificationPrefs") or {}
    return prefs.get("push", True) and prefs.get("priceAlerts", True)


@dataclass
class AlertRunResult:
    evaluated: int = 0
    notified: int = 0
    rearmed: int = 0
    pushes_sent: int = 0
    invalid_tokens: int = 0


def _chunks(items: list, size: int):
    for i in range(0, len(items), size):
        yield items[i:i + size]


def _alerts_to_evaluate(db, product_ids: set[str]) -> dict[str, firestore.DocumentSnapshot]:
    found: dict[str, firestore.DocumentSnapshot] = {}
    alerts = db.collection_group("alerts")
    for chunk in _chunks(sorted(product_ids), 30):  # límite de "in" en Firestore
        query = (alerts.where(filter=FieldFilter("productId", "in", chunk))
                 .where(filter=FieldFilter("status", "==", "ACTIVE")))
        for snap in query.stream():
            found[snap.reference.path] = snap
    never = (alerts.where(filter=FieldFilter("status", "==", "ACTIVE"))
             .where(filter=FieldFilter("evaluatedAt", "==", None)))
    for snap in never.stream():
        found[snap.reference.path] = snap
    return found


def _send_push(db, uid: str, title: str, body: str, data: dict, result: AlertRunResult) -> None:
    """Envía la notificación a los dispositivos activos del usuario (FCM)."""
    if using_emulator():
        return  # FCM no tiene emulador: en desarrollo solo se crea la notificación en la bandeja
    from firebase_admin import messaging

    devices = [d for d in db.collection("users").document(uid).collection("devices")
               .where(filter=FieldFilter("status", "==", "ACTIVE")).stream()]
    tokens = [(d, (d.to_dict() or {}).get("pushToken")) for d in devices]
    tokens = [(d, t) for d, t in tokens if t]
    if not tokens:
        return
    response = messaging.send_each_for_multicast(messaging.MulticastMessage(
        tokens=[t for _, t in tokens],
        notification=messaging.Notification(title=title, body=body),
        data={k: str(v) for k, v in data.items()},
        android=messaging.AndroidConfig(priority="high"),
    ))
    result.pushes_sent += response.success_count
    for (device, _), r in zip(tokens, response.responses):
        if not r.success and r.exception is not None and r.exception.code in ("NOT_FOUND", "INVALID_ARGUMENT", "UNREGISTERED"):
            device.reference.update({"status": "INVALID"})  # token vencido: no reintentar
            result.invalid_tokens += 1


def evaluate_alerts(db, product_ids: set[str], now: datetime | None = None) -> AlertRunResult:
    """Evalúa alertas, crea notificaciones y envía push. Devuelve contadores para el job."""
    now = now or datetime.now(timezone.utc)
    result = AlertRunResult()
    alerts = _alerts_to_evaluate(db, product_ids)
    if not alerts:
        return result

    products: dict[str, dict] = {}
    stores = {s.id: s.to_dict() or {} for s in db.collection("stores").stream()}
    users: dict[str, dict] = {}

    for path, snap in alerts.items():
        alert = snap.to_dict() or {}
        pid = alert.get("productId")
        if pid not in products:
            psnap = db.collection("products").document(pid).get()
            products[pid] = psnap.to_dict() if psnap.exists else {}
        summary = products[pid].get("summary") or {}
        best = fresh_best_price(summary, stores.get(summary.get("minPriceStoreCode")), now)
        target = int(alert.get("targetPriceCents") or 0)
        decision = decide_alert(target, alert.get("lastTriggeredPriceCents"), best)
        result.evaluated += 1

        update: dict = {"evaluatedAt": now}
        if decision == REARM:
            update["lastTriggeredPriceCents"] = None
            result.rearmed += 1
        elif decision == NOTIFY:
            update.update({"lastTriggeredAt": now, "lastTriggeredPriceCents": best})
            uid = snap.reference.parent.parent.id
            store_code = summary.get("minPriceStoreCode")
            store_name = (stores.get(store_code) or {}).get("name", store_code or "una tienda")
            product_name = products[pid].get("displayName") or alert.get("productName") or "Tu producto"
            title, body = alert_message(product_name, best, store_name, target)
            payload = {"productId": pid, "priceCents": best, "storeCode": store_code, "alertId": snap.id}
            db.collection("users").document(uid).collection("notifications").add({
                "type": "PRICE_ALERT", "title": title, "message": body, "payload": payload,
                "readAt": None, "createdAt": now,
            })
            result.notified += 1
            if uid not in users:
                usnap = db.collection("users").document(uid).get()
                users[uid] = usnap.to_dict() if usnap.exists else {}
            if wants_price_alert_push(users[uid]):
                try:
                    _send_push(db, uid, title, body, payload, result)
                except Exception as exc:  # una falla de FCM no debe tumbar la corrida
                    logger.warning("No se pudo enviar push a %s: %s", uid, exc)
        snap.reference.update(update)
    return result
