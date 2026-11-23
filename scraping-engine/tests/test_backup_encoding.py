import json
from datetime import datetime, timezone

from google.cloud.firestore_v1 import GeoPoint

from app.backup.export import CATALOG_COLLECTIONS, USER_COLLECTIONS, decode_value, encode_value


def test_roundtrip_preserves_types():
    original = {
        "price": 24990,
        "ratio": 0.5,
        "name": "Kingston NV3 — 1TB ñ",
        "nothing": None,
        "flag": True,
        "when": datetime(2026, 11, 23, 5, 30, tzinfo=timezone.utc),
        "where": GeoPoint(-12.0464, -77.0428),
        "raw": b"\x00\x01",
        "points": [{"t": datetime(2026, 11, 1, tzinfo=timezone.utc), "p": 100}],
        "nested": {"summary": {"lastCheckedAt": datetime(2026, 11, 2, tzinfo=timezone.utc)}},
    }
    as_json = json.dumps(encode_value(original), ensure_ascii=False)
    restored = decode_value(json.loads(as_json))
    assert restored == original


def test_personal_data_is_not_in_catalog_backup():
    assert "users" not in CATALOG_COLLECTIONS
    assert USER_COLLECTIONS == ["users"]
