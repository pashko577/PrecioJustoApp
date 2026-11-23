"""Fotos de producto en listados HTML y foto elegida para el producto."""

from datetime import datetime, timedelta, timezone

from app.postprocess.summary import product_image
from app.spiders.images import first_image_url


def test_plain_src_magento():
    chunk = '<img class="product-image-photo" src="https://www.efe.com.pe/media/a.jpg?quality=85&amp;width=400" loading="lazy"/>'
    assert first_image_url(chunk) == "https://www.efe.com.pe/media/a.jpg?quality=85&width=400"


def test_lazy_data_src_wins_over_placeholder():
    chunk = ('<img src="data:image/svg+xml,%3Csvg%3E" data-src="https://infotec.com.pe/1-home_default/x.jpg" '
             'alt="x">')
    assert first_image_url(chunk) == "https://infotec.com.pe/1-home_default/x.jpg"


def test_attributes_without_spaces_prestashop():
    chunk = '<img src="https://sercoplus.com/58327-home_default/laptop.jpg"alt="LAPTOP"class="x" loading="lazy">'
    assert first_image_url(chunk) == "https://sercoplus.com/58327-home_default/laptop.jpg"


def test_relative_and_protocol_relative_urls():
    assert first_image_url('<img src="/files/a.jpg">', "https://www.memorykings.pe") == "https://www.memorykings.pe/files/a.jpg"
    assert first_image_url('<img src="//cdn.x.pe/a.jpg">') == "https://cdn.x.pe/a.jpg"


def test_no_image():
    assert first_image_url('<div>sin foto</div>') is None
    assert first_image_url('<img src="data:image/gif;base64,R0l">') is None


NOW = datetime(2026, 11, 23, tzinfo=timezone.utc)


def offer(store, image, days_old, **extra):
    return {"storeCode": store, "imageUrl": image, "createdAt": NOW - timedelta(days=days_old),
            "status": "ACTIVE", "matchStatus": "MATCHED_AUTO", **extra}


def test_product_image_is_the_oldest_confirmed_offer_with_photo():
    offers = [offer("B", "https://b/new.jpg", 1), offer("A", "https://a/old.jpg", 30), offer("C", None, 90)]
    assert product_image(offers) == "https://a/old.jpg"


def test_product_image_ignores_unconfirmed_or_inactive_offers():
    offers = [offer("A", "https://a.jpg", 30, matchStatus="PENDING_REVIEW"),
              offer("B", "https://b.jpg", 20, status="INACTIVE"),
              offer("C", "https://c.jpg", 1)]
    assert product_image(offers) == "https://c.jpg"
    assert product_image([offer("A", None, 3)]) is None


def test_offer_is_rewritten_once_when_it_gains_a_photo():
    from app.pipelines.firestore import needs_write

    base = {"status": "ACTIVE", "missedRuns": 0, "currentPriceCents": 100, "title": "x"}
    assert needs_write({**base, "imageUrl": None}, {**base, "imageUrl": "https://a.jpg"})
    # Ya tenía foto: un cambio de URL (parámetros de caché) no gasta una escritura.
    assert not needs_write({**base, "imageUrl": "https://a.jpg?v=1"}, {**base, "imageUrl": "https://a.jpg?v=2"})
    assert not needs_write({**base, "imageUrl": "https://a.jpg"}, {**base, "imageUrl": None})
