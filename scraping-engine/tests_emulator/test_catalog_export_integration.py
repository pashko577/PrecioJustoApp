"""Exportación del catálogo público (`catalog.json`) contra el emulador."""

from datetime import datetime, timedelta, timezone

from firebase_admin import firestore


def _seed(db):
    db.document("stores/COOLBOX").set({"name": "Coolbox", "freshnessMinutes": 1440, "scrapingEnabled": True,
                                       "lastCompleteRunAt": datetime(2026, 11, 24, tzinfo=timezone.utc)})
    db.document("products/ps5").set({"displayName": "PS5 Slim", "brand": "Sony", "categorySlug": "consolas",
                                      "status": "ACTIVE", "summary": {"minPriceCents": 200_000, "offerCount": 1},
                                      "updatedAt": firestore.SERVER_TIMESTAMP})
    db.document("products/viejo").set({"displayName": "Viejo", "status": "MERGED", "mergedInto": "ps5",
                                       "updatedAt": firestore.SERVER_TIMESTAMP})
    base = {"productId": "ps5", "storeCode": "COOLBOX", "status": "ACTIVE", "currentPriceCents": 200_000,
            "availability": "AVAILABLE", "missedRuns": 0, "updatedAt": firestore.SERVER_TIMESTAMP}
    db.document("storeProducts/COOLBOX__1").set({**base, "matchStatus": "MATCHED_AUTO"})
    db.document("storeProducts/COOLBOX__2").set({**base, "matchStatus": "PENDING_REVIEW"})  # no se muestra


def test_full_export_only_includes_what_the_app_shows(db):
    from app.export.catalog import build_catalog

    _seed(db)
    catalog, stats = build_catalog(db, None)
    assert not stats["incremental"]
    products = {p["id"]: p for p in catalog["products"]}
    assert products["ps5"]["name"] == "PS5 Slim" and products["ps5"]["summary"]["minPriceCents"] == 200_000
    assert products["viejo"] == {"id": "viejo", "status": "MERGED", "mergedInto": "ps5"}
    assert [o["id"] for o in catalog["offers"]] == ["COOLBOX__1"]
    assert "missedRuns" not in catalog["offers"][0]  # 0 se omite
    assert catalog["stores"][0]["lastCompleteRunAt"] == "2026-11-24T00:00:00Z"
    assert any(c["slug"] == "consolas" for c in catalog["categories"])


def test_incremental_export_reads_only_changes(db):
    from app.export.catalog import build_catalog

    _seed(db)
    first, _ = build_catalog(db, None)
    # La exportación anterior fue "hace una hora" (fuera del margen): solo lo nuevo se lee.
    first["generatedAt"] = (datetime.now(timezone.utc) + timedelta(hours=1)).isoformat()
    db.document("storeProducts/COOLBOX__1").update({"currentPriceCents": 180_000,
                                                    "updatedAt": datetime.now(timezone.utc) + timedelta(hours=2)})
    db.document("products/ps5").update({"status": "INACTIVE",
                                        "updatedAt": datetime.now(timezone.utc) + timedelta(hours=2)})
    second, stats = build_catalog(db, first)
    assert stats["incremental"]
    assert stats["reads"] == 2 + 1  # producto y publicación cambiados + la tienda
    assert "ps5" not in {p["id"] for p in second["products"]}
    assert second["offers"] == []  # sus ofertas se van con él


def test_main_writes_file_and_records_quota(db, tmp_path):
    import json

    from app.export.catalog import main
    from app.quota import quota_day

    _seed(db)
    out = tmp_path / "catalog.json"
    assert main(["--out", str(out), "--previous-file", str(tmp_path / "no-existe.json")]) == 0
    assert json.loads(out.read_text("utf-8"))["version"] == 1
    used = db.document(f"system/quota-{quota_day()}").get().to_dict()
    assert used["reads"] >= 5


def test_main_keeps_published_catalog_without_quota(db, tmp_path):
    import json

    from app.export.catalog import PROJECT_DAILY_READS_CAP, main
    from app.quota import quota_day

    _seed(db)
    db.document(f"system/quota-{quota_day()}").set({"reads": PROJECT_DAILY_READS_CAP})
    published = tmp_path / "publicado.json"
    published.write_text(json.dumps({"version": 1, "generatedAt": "2026-11-24T00:00:00Z", "products": [],
                                      "offers": [], "stores": [], "categories": []}), "utf-8")
    out = tmp_path / "catalog.json"
    assert main(["--out", str(out), "--previous-file", str(published)]) == 0
    assert json.loads(out.read_text("utf-8"))["generatedAt"] == "2026-11-24T00:00:00Z"  # sin cambios
