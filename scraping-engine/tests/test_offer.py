from datetime import datetime

import pytest

from app.models.offer import InvalidOfferError, ScrapedOffer


def make(**overrides):
    data = dict(
        store_code="DEMO_STORE",
        external_product_id="KNV3-1TB",
        title="Kingston NV3 1TB",
        price_cents=24990,
        product_url="https://demo.example.com/p/KNV3-1TB",
        availability="AVAILABLE",
    )
    data.update(overrides)
    return ScrapedOffer(**data)


def test_valid_offer_passes():
    offer = make().validate()
    assert offer.doc_id == "DEMO_STORE__KNV3-1TB"
    assert offer.shipping_cents is None  # desconocido por defecto, no 0


@pytest.mark.parametrize(
    "overrides",
    [
        {"price_cents": 249.90},
        {"price_cents": 0},
        {"price_cents": True},
        {"currency": "USD"},
        {"availability": "EN_STOCK"},
        {"condition": "SEMINUEVO"},
        {"store_code": "demo"},
        {"external_product_id": "a/b"},
        {"title": ""},
        {"shipping_cents": -1},
        {"product_url": "javascript:alert(1)"},
        {"checked_at": datetime(2026, 11, 22)},  # sin zona horaria
    ],
)
def test_invalid_offers_rejected(overrides):
    with pytest.raises(InvalidOfferError):
        make(**overrides).validate()
