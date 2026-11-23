from datetime import datetime, timedelta, timezone

from app.admin.status import DISABLED, NEVER, OK, STALE, render, store_health

NOW = datetime(2026, 11, 23, 12, tzinfo=timezone.utc)


def test_store_health():
    assert store_health({"scrapingEnabled": False}, NOW) == DISABLED
    assert store_health({"scrapingEnabled": True}, NOW) == NEVER
    six_h = {"scrapingEnabled": True, "scrapingIntervalMinutes": 360}
    assert store_health(six_h | {"lastCompleteRunAt": NOW - timedelta(hours=12)}, NOW) == OK
    assert store_health(six_h | {"lastCompleteRunAt": NOW - timedelta(hours=14)}, NOW) == STALE
    twelve_h = {"scrapingEnabled": True, "scrapingIntervalMinutes": 720}
    assert store_health(twelve_h | {"lastCompleteRunAt": NOW - timedelta(hours=20)}, NOW) == OK


def test_render_markdown():
    report = {"now": NOW, "products": 1234, "pendingReview": 3, "unmatched": 0, "stores": [
        {"code": "COOLBOX", "name": "Coolbox", "health": OK, "lastRunAt": NOW, "lastRunStatus": "SUCCESS",
         "lastCompleteRunAt": NOW - timedelta(hours=2), "listings": 812},
    ]}
    md = render(report, markdown=True)
    assert "| Coolbox | ✅ OK | hace 2 h | SUCCESS | 812 |" in md
    assert "Productos activos: **1,234**" in md
