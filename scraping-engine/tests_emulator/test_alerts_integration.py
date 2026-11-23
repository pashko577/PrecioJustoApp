from datetime import datetime, timezone

from app.postprocess.alerts import evaluate_alerts

NOW = datetime.now(timezone.utc)


def seed(db):
    db.document("stores/COOLBOX").set({"name": "Coolbox", "freshnessMinutes": 720, "lastCompleteRunAt": NOW})
    db.document("products/nv3").set({"displayName": "Kingston NV3 1TB", "summary": {
        "minPriceCents": 24990, "minPriceStoreCode": "COOLBOX", "lastCheckedAt": NOW}})
    user = db.collection("users").document("ana")
    user.set({"email": "ana@correo.pe", "plan": "FREE", "notificationPrefs": {"push": True, "priceAlerts": True}})
    base = {"productId": "nv3", "productName": "Kingston NV3 1TB", "currency": "PEN", "condition": "AT_OR_BELOW",
            "status": "ACTIVE", "lastTriggeredPriceCents": None, "lastTriggeredAt": None, "evaluatedAt": None}
    user.collection("alerts").document("cumple").set({**base, "targetPriceCents": 26000})
    user.collection("alerts").document("no_cumple").set({**base, "targetPriceCents": 20000})
    user.collection("alerts").document("pausada").set({**base, "targetPriceCents": 26000, "status": "PAUSED"})
    return user


def notifications(user):
    return [n.to_dict() for n in user.collection("notifications").stream()]


def test_alert_cycle(db):
    user = seed(db)
    r = evaluate_alerts(db, set())  # recién creadas: se evalúan aunque el producto no cambió
    assert (r.evaluated, r.notified) == (2, 1)
    [n] = notifications(user)
    assert n["type"] == "PRICE_ALERT" and n["readAt"] is None
    assert n["message"] == "Kingston NV3 1TB está a S/ 249.90 en Coolbox (tu alerta: S/ 260.00)."
    assert n["payload"]["productId"] == "nv3"

    assert evaluate_alerts(db, {"nv3"}).notified == 0          # mismo precio: no repite
    db.document("products/nv3").update({"summary.minPriceCents": 27000})
    assert evaluate_alerts(db, {"nv3"}).rearmed == 1           # supera el objetivo: rearma
    db.document("products/nv3").update({"summary.minPriceCents": 23990})
    assert evaluate_alerts(db, {"nv3"}).notified == 1          # vuelve a cumplir: avisa
    assert len(notifications(user)) == 2
    assert user.collection("alerts").document("pausada").get().to_dict()["evaluatedAt"] is None


def test_stale_price_never_notifies(db):
    user = seed(db)
    db.document("stores/COOLBOX").update({"lastCompleteRunAt": datetime(2026, 1, 1, tzinfo=timezone.utc)})
    db.document("products/nv3").update({"summary.lastCheckedAt": datetime(2026, 1, 1, tzinfo=timezone.utc)})
    assert evaluate_alerts(db, set()).notified == 0
    assert notifications(user) == []
