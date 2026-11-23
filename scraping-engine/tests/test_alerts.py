import pytest

from app.postprocess.alerts import (
    NOTHING,
    NOTIFY,
    REARM,
    alert_message,
    decide_alert,
    format_soles,
    wants_price_alert_push,
)


@pytest.mark.parametrize(
    ("target", "last", "best", "expected"),
    [
        (23050, None, 22900, NOTIFY),     # cumple por primera vez
        (23050, None, 23050, NOTIFY),     # igual al objetivo también cumple
        (23050, 22900, 22900, NOTHING),   # mismo precio: no repetir (RN-08)
        (23050, 22900, 23000, NOTHING),   # subió pero sigue bajo el objetivo: no repetir
        (23050, 22900, 21900, NOTIFY),    # bajó todavía más: avisar de nuevo
        (23050, 22900, 25000, REARM),     # pasó el objetivo: se rearma
        (23050, None, 25000, NOTHING),    # no cumple y nunca avisó
        (23050, 22900, None, NOTHING),    # sin precio vigente: no decidir
    ],
)
def test_decide_alert(target, last, best, expected):
    assert decide_alert(target, last, best) == expected


def test_full_cycle_rearm_then_notify_again():
    last = None
    seen = []
    for price in [25000, 22900, 22900, 25500, 23000]:
        d = decide_alert(23050, last, price)
        seen.append(d)
        if d == NOTIFY:
            last = price
        elif d == REARM:
            last = None
    assert seen == [NOTHING, NOTIFY, NOTHING, REARM, NOTIFY]


def test_message_format():
    assert format_soles(123456789) == "S/ 1,234,567.89"
    title, body = alert_message("Kingston NV3 1TB", 22900, "Coolbox", 23050)
    assert title == "¡Bajó de precio!"
    assert body == "Kingston NV3 1TB está a S/ 229.00 en Coolbox (tu alerta: S/ 230.50)."


def test_push_preferences():
    assert wants_price_alert_push(None)                                    # por defecto sí
    assert wants_price_alert_push({"notificationPrefs": {"push": True, "priceAlerts": True}})
    assert not wants_price_alert_push({"notificationPrefs": {"push": False}})
    assert not wants_price_alert_push({"notificationPrefs": {"push": True, "priceAlerts": False}})


def test_never_notify_with_stale_price():
    from datetime import datetime, timedelta, timezone

    from app.postprocess.alerts import fresh_best_price
    now = datetime(2026, 11, 23, 12, tzinfo=timezone.utc)
    summary = {"minPriceCents": 22900, "lastCheckedAt": now - timedelta(days=3)}
    assert fresh_best_price(summary, {"freshnessMinutes": 720}, now) is None          # vencido
    store_ran = {"freshnessMinutes": 720, "lastCompleteRunAt": now - timedelta(hours=1)}
    assert fresh_best_price(summary, store_ran, now) == 22900                         # confirmado por la corrida
    assert fresh_best_price({"minPriceCents": None}, store_ran, now) is None
