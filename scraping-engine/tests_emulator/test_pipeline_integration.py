"""Pipeline de Firestore contra el emulador: escrituras de un producto nuevo y su historial."""

import logging
from datetime import datetime, timedelta, timezone
from types import SimpleNamespace

from app.models.offer import ScrapedOffer


def _offer(price: int, checked_at: datetime) -> ScrapedOffer:
    return ScrapedOffer(
        store_code="COOLBOX", external_product_id="1", title="Consola Sony PlayStation 5 Slim CFI-2015",
        price_cents=price, product_url="https://example.com/ps5", availability="AVAILABLE", brand="Sony",
        model="CFI-2015", identifiers={"MPN": "CFI2015"}, category_hint="consolas",
        image_url="https://example.com/ps5.jpg", checked_at=checked_at,
    )


def _run(offer: ScrapedOffer):
    from app.pipelines.firestore import FirestorePipeline

    spider = SimpleNamespace(store_code="COOLBOX", logger=logging.getLogger("test"), job_errors=[], max_pages=None)
    pipeline = FirestorePipeline()
    pipeline.crawler = SimpleNamespace(spider=spider, stats=SimpleNamespace(get_value=lambda _k, d=0: d))
    pipeline.open_spider(spider)
    pipeline.process_item(offer, spider)
    pipeline.close_spider(spider)
    return pipeline


def test_new_product_costs_two_writes_and_history_starts_on_first_change(db):
    db.document("stores/COOLBOX").set({"name": "Coolbox", "freshnessMinutes": 1440})
    first = datetime.now(timezone.utc) - timedelta(days=1)

    run = _run(_offer(200_000, first))
    # Publicación + producto (con su resumen): sin historial ni reescritura del resumen.
    assert run.counters["written"] == 1 and run.matcher.created_products == 1
    assert run.affected_products == set()
    listing = db.document("storeProducts/COOLBOX__1").get().to_dict()
    assert listing["historyStarted"] is False
    assert not list(db.collection("storeProducts/COOLBOX__1/history").stream())
    product = db.document(f"products/{listing['productId']}").get().to_dict()
    assert product["summary"]["minPriceCents"] == 200_000
    assert product["summary"]["offerCount"] == 1
    assert product.get("imageUrl") is None  # Coolbox no dio permiso para sus fotos (showImages)

    second = datetime.now(timezone.utc)
    _run(_offer(180_000, second))
    month_docs = list(db.collection("storeProducts/COOLBOX__1/history").stream())
    points = sorted((p for d in month_docs for p in d.to_dict()["points"]), key=lambda p: p["t"])
    assert [p["p"] for p in points] == [200_000, 180_000]  # estado inicial + cambio
    assert db.document("storeProducts/COOLBOX__1").get().to_dict()["historyStarted"] is True
    product = db.document(f"products/{listing['productId']}").get().to_dict()
    assert product["summary"]["minPriceCents"] == 180_000


def test_clear_disallowed_images_keeps_only_permitted_stores(db):
    from app.admin.images import clear_disallowed_images

    db.document("stores/COOLBOX").set({"name": "Coolbox", "showImages": False})
    db.document("stores/OECHSLE").set({"name": "Oechsle", "showImages": True})
    db.document("products/a").set({"imageUrl": "https://a.jpg"})  # antiguo, sin tienda registrada
    db.document("products/b").set({"imageUrl": "https://b.jpg", "imageStoreCode": "COOLBOX"})
    db.document("products/c").set({"imageUrl": "https://c.jpg", "imageStoreCode": "OECHSLE"})
    db.document("products/d").set({"displayName": "sin foto"})

    assert clear_disallowed_images(db) == 2
    assert "imageUrl" not in db.document("products/a").get().to_dict()
    assert "imageUrl" not in db.document("products/b").get().to_dict()
    assert db.document("products/c").get().to_dict()["imageUrl"] == "https://c.jpg"
    assert clear_disallowed_images(db) == 0  # idempotente


def test_clear_keeps_unknown_store_images_when_all_active_stores_allow_photos(db):
    from app.admin.images import clear_disallowed_images

    db.document("stores/COOLBOX").set({"scrapingEnabled": True, "showImages": True})
    db.document("stores/EFE").set({"scrapingEnabled": False, "showImages": False})
    db.document("products/a").set({"imageUrl": "https://a.jpg"})  # antiguo, sin tienda registrada
    db.document("products/e").set({"imageUrl": "https://e.jpg", "imageStoreCode": "EFE"})
    assert clear_disallowed_images(db) == 1  # solo la de la tienda sin permiso
    assert db.document("products/a").get().to_dict()["imageUrl"] == "https://a.jpg"
    db.document("stores/COOLBOX").update({"showImages": False})
    assert clear_disallowed_images(db) == 1
