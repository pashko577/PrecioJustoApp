"""Bajada de precio del resumen («Bajó X %»): solo con precios observados por CompraMejor."""

from datetime import datetime, timedelta, timezone

from app.postprocess.summary import compute_summary

NOW = datetime(2026, 11, 23, 12, tzinfo=timezone.utc)


def offer(store, price, previous=None, changed_days_ago=1, **extra):
    return {
        "storeCode": store, "currentPriceCents": price, "previousPriceCents": previous,
        "lastChangedAt": NOW - timedelta(days=changed_days_ago), "status": "ACTIVE",
        "availability": "AVAILABLE", "currency": "PEN", "lastCheckedAt": NOW, "missedRuns": 0,
        "matchStatus": "MATCHED_AUTO", **extra,
    }


def summary(*offers):
    return compute_summary(list(offers), {}, now=NOW)


def test_drop_of_the_cheapest_store():
    s = summary(offer("A", 26900, previous=32900))
    assert s["priceDropFromCents"] == 32900
    assert s["priceDropPercent"] == 18
    assert s["priceDroppedAt"] == NOW - timedelta(days=1)


def test_drop_is_measured_against_the_previous_best_price_of_the_product():
    # A bajó de 120 a 100, pero B ya lo tenía a 105: la bajada real es de 105 a 100.
    s = summary(offer("A", 10000, previous=12000), offer("B", 10500))
    assert s["priceDropFromCents"] == 10500
    assert s["priceDropPercent"] == 5


def test_no_drop_if_another_store_was_already_cheaper():
    s = summary(offer("A", 10000, previous=12000), offer("B", 10000))
    assert s["priceDropPercent"] is None


def test_list_price_is_never_used():
    s = summary(offer("A", 129900, listPriceCents=269900))
    assert s["priceDropPercent"] is None and s["priceDropFromCents"] is None


def test_old_drops_are_not_announced():
    assert summary(offer("A", 26900, previous=32900, changed_days_ago=8))["priceDropPercent"] is None


def test_price_increase_is_not_a_drop():
    assert summary(offer("A", 32900, previous=26900))["priceDropPercent"] is None


def test_implausible_drop_is_ignored():
    assert summary(offer("A", 1000, previous=100000))["priceDropPercent"] is None


def test_drop_fields_always_present_to_clear_old_values():
    s = summary(offer("A", 26900))
    assert {"priceDropFromCents", "priceDropPercent", "priceDroppedAt"} <= s.keys()
