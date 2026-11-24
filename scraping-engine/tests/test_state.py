from datetime import datetime, timedelta, timezone

from app.state import (MAX_STATE_AGE, EngineState, listing_doc, load_store_listings, product_doc,
                       save_store_listings)

NOW = datetime(2026, 11, 25, 12, tzinfo=timezone.utc)


def test_state_round_trip_keeps_dates_and_drops_heavy_fields(tmp_path):
    state = EngineState(NOW, {"p1": product_doc({"displayName": "PS5", "searchTokens": ["ps5"],
                                                 "summary": {"lastCheckedAt": NOW}})},
                        {"COOLBOX__1": listing_doc({"storeCode": "COOLBOX", "titleTokens": ["x"],
                                                    "matchAttemptedAt": NOW - timedelta(days=1)})})
    path = tmp_path / "engine-state.json.gz"
    state.save(path)
    loaded = EngineState.load(path, now=NOW)
    assert loaded.generated_at == NOW
    assert loaded.products["p1"] == {"displayName": "PS5", "summary": {"lastCheckedAt": NOW}}
    assert loaded.listings["COOLBOX__1"]["matchAttemptedAt"] == NOW - timedelta(days=1)
    assert "titleTokens" not in loaded.listings["COOLBOX__1"]
    assert loaded.store_listings("COOLBOX").keys() == {"COOLBOX__1"}
    assert loaded.store_listings("OECHSLE") == {}


def test_old_damaged_or_missing_state_is_not_used(tmp_path):
    path = tmp_path / "engine-state.json.gz"
    EngineState(NOW - MAX_STATE_AGE - timedelta(hours=1)).save(path)
    assert EngineState.load(path, now=NOW) is None  # muy vieja: se vuelve a leer Firestore
    path.write_bytes(b"no es gzip")
    assert EngineState.load(path, now=NOW) is None
    assert EngineState.load(tmp_path / "no-existe.json.gz") is None
    assert EngineState.load(None) is None


def test_store_listings_files(tmp_path):
    save_store_listings(tmp_path / "out", "COOLBOX", {"COOLBOX__1": {"storeCode": "COOLBOX", "titleTokens": ["a"]}})
    (tmp_path / "out" / "roto.json.gz").write_bytes(b"x")
    runs = load_store_listings(tmp_path / "out")
    assert runs == {"COOLBOX": {"COOLBOX__1": {"storeCode": "COOLBOX"}}}
    assert load_store_listings(tmp_path / "vacio") == {}
