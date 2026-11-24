"""Presupuesto diario de Firestore (plan gratuito) y reintentos espaciados."""

from datetime import datetime, timedelta, timezone

from app.matching.matcher import should_retry_unmatched
from app.models.offer import ScrapedOffer
from app.quota import (
    CLOSE_RESERVE_WRITES, ENGINE_DAILY_READS, ENGINE_DAILY_WRITES, RUN_MAX_READS, RUN_MAX_WRITES, quota_day,
    run_budget,
)


def test_quota_day_resets_at_pacific_midnight():
    # 07:59 UTC del 24 = 23:59 del 23 en el Pacífico (UTC-8): sigue siendo el día 23.
    assert quota_day(datetime(2026, 11, 24, 7, 59, tzinfo=timezone.utc)) == "2026-11-23"
    assert quota_day(datetime(2026, 11, 24, 8, 1, tzinfo=timezone.utc)) == "2026-11-24"


def test_run_budget_caps_per_run_and_per_day():
    fresh = run_budget(0, 0)
    assert (fresh.reads, fresh.writes) == (RUN_MAX_READS, RUN_MAX_WRITES) and not fresh.exhausted
    late = run_budget(ENGINE_DAILY_READS - 500, ENGINE_DAILY_WRITES - 1000)
    assert (late.reads, late.writes) == (500, 1000)
    assert run_budget(0, ENGINE_DAILY_WRITES - CLOSE_RESERVE_WRITES).exhausted
    assert run_budget(ENGINE_DAILY_READS + 10, 0).reads == 0
    # El motor nunca se reserva toda la cuota gratuita: queda margen para la app.
    assert ENGINE_DAILY_READS < 50_000 and ENGINE_DAILY_WRITES < 20_000


def offer(title="Laptop X", identifiers=None, checked=None):
    return ScrapedOffer(store_code="A", external_product_id="1", title=title, price_cents=100,
                        product_url="https://x", identifiers=identifiers or {},
                        checked_at=checked or datetime(2026, 11, 23, tzinfo=timezone.utc))


def test_unmatched_retry_is_spaced_unless_the_listing_changed():
    now = datetime(2026, 11, 23, tzinfo=timezone.utc)
    recent = {"title": "Laptop X", "identifiers": {}, "matchAttemptedAt": now - timedelta(days=1)}
    assert not should_retry_unmatched(offer(), recent, now)
    assert should_retry_unmatched(offer(), {**recent, "matchAttemptedAt": now - timedelta(days=4)}, now)
    assert should_retry_unmatched(offer(), {"title": "Laptop X", "identifiers": {}}, now)  # nunca se intentó
    assert should_retry_unmatched(offer(title="Laptop X 16GB"), recent, now)
    assert should_retry_unmatched(offer(identifiers={"MPN": "ABC123"}), recent, now)


def test_scope_pages_from_store_config():
    from app.spiders.magento.registry import SPIDERS as MAGENTO
    from app.spiders.vtex.registry import SPIDERS as VTEX
    assert VTEX["plazavea"].scope_pages == 4   # 200 productos por categoría
    assert MAGENTO["efe"].scope_pages == 6


def test_pipeline_skips_store_when_project_quota_is_exhausted(monkeypatch):
    """Un 429 al iniciar (cupo del proyecto agotado) salta la tienda sin fallar ni hacer solicitudes."""
    from types import SimpleNamespace

    import pytest
    from google.api_core.exceptions import ResourceExhausted
    from scrapy.exceptions import CloseSpider

    from app.pipelines import firestore as pipeline_module

    class ExhaustedDb:
        def collection(self, _name):
            raise ResourceExhausted("Quota exceeded.")

    monkeypatch.setattr(pipeline_module, "get_db", lambda: ExhaustedDb())
    monkeypatch.setattr(pipeline_module, "QuotaTracker", lambda db: SimpleNamespace(record=None))
    logger = SimpleNamespace(warning=lambda *a, **k: None)
    spider = SimpleNamespace(store_code="PLAZAVEA", logger=logger)
    pipeline = pipeline_module.FirestorePipeline()
    pipeline.crawler = SimpleNamespace(spider=spider)

    with pytest.raises(CloseSpider):
        pipeline.open_spider(spider)
    assert spider.not_due is True
    pipeline.close_spider(spider)  # no intenta registrar el uso (también fallaría)
