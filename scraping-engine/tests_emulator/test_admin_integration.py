from datetime import datetime, timedelta, timezone

import pytest

from app.admin import review_matches as review
from app.admin.categories import upload_categories
from app.admin.set_role import set_role
from app.admin.status import NEVER, OK, collect
from app.backup.export import export
from app.backup.restore import restore
from app.catalog import flatten_categories

NOW = datetime.now(timezone.utc)


def seed_review(db):
    upload_categories(db, flatten_categories())
    db.document("stores/COOLBOX").set({"name": "Coolbox", "freshnessMinutes": 720, "scrapingEnabled": True,
                                       "scrapingIntervalMinutes": 360, "lastCompleteRunAt": NOW})
    db.document("products/lenovo-slim3-r5").set({"displayName": "Lenovo IdeaPad Slim 3 Ryzen 5", "brand": "Lenovo",
                                                  "categorySlug": "laptops", "status": "ACTIVE", "summary": {}})
    db.document("products/lenovo-slim3-r7").set({"displayName": "Lenovo IdeaPad Slim 3 Ryzen 7", "brand": "Lenovo",
                                                  "categorySlug": "laptops", "status": "ACTIVE", "summary": {}})
    base = {"storeCode": "COOLBOX", "status": "ACTIVE", "availability": "AVAILABLE", "currency": "PEN",
            "lastCheckedAt": NOW, "missedRuns": 0, "categoryHint": "laptops", "brand": "Lenovo", "createdAt": NOW}
    db.document("storeProducts/COOLBOX__1").set({**base, "externalProductId": "1", "currentPriceCents": 229900,
        "title": "Laptop Lenovo IdeaPad Slim 3 Ryzen 5 16GB", "productId": "lenovo-slim3-r5",
        "matchStatus": "PENDING_REVIEW", "matchScore": 80})
    db.document("storeProducts/COOLBOX__2").set({**base, "externalProductId": "2", "currentPriceCents": 279900,
        "title": "Laptop Lenovo IdeaPad Slim 3 Ryzen 7 16GB", "productId": "lenovo-slim3-r5",
        "matchStatus": "PENDING_REVIEW", "matchScore": 80, "identifiers": {"MPN": "83K1"}})
    db.document("storeProducts/COOLBOX__3").set({**base, "externalProductId": "3", "currentPriceCents": 99900,
        "title": "Funda para laptop", "productId": None, "matchStatus": "UNMATCHED", "matchScore": None})


def test_review_flow(db):
    seed_review(db)
    pending = review.list_listings(db)
    assert {p["id"] for p in pending} == {"COOLBOX__1", "COOLBOX__2"}

    # Aprobar la sugerencia correcta: el producto recibe el precio.
    assert review.approve(db, "COOLBOX__1") == "lenovo-slim3-r5"
    listing = db.document("storeProducts/COOLBOX__1").get().to_dict()
    assert (listing["matchStatus"], listing["productId"]) == ("MATCHED_MANUAL", "lenovo-slim3-r5")
    assert db.document("products/lenovo-slim3-r5").get().to_dict()["summary"]["minPriceCents"] == 229900

    # Reasignar la sugerencia equivocada (Ryzen 7) al producto correcto.
    review.assign(db, "COOLBOX__2", "lenovo-slim3-r7")
    assert db.document("products/lenovo-slim3-r7").get().to_dict()["summary"]["minPriceCents"] == 279900

    # Rechazar: sin producto.
    review.reject(db, "COOLBOX__3")
    assert db.document("storeProducts/COOLBOX__3").get().to_dict()["matchStatus"] == "REJECTED"

    # Auditoría de las tres acciones.
    actions = sorted(a.to_dict()["action"] for a in db.collection("auditLogs").stream())
    assert actions == ["MATCH_APPROVED", "MATCH_ASSIGNED", "MATCH_REJECTED"]


def test_review_errors_and_create(db):
    seed_review(db)
    with pytest.raises(review.ReviewError):
        review.assign(db, "COOLBOX__1", "no-existe")
    with pytest.raises(review.ReviewError):
        review.approve(db, "COOLBOX__3")  # sin sugerencia
    product_id = review.create(db, "COOLBOX__2")
    created = db.document(f"products/{product_id}").get().to_dict()
    assert created["categorySlug"] == "laptops"
    assert "MPN:83K1" in created["identifierKeys"]
    assert created["summary"]["minPriceCents"] == 279900
    assert created["source"] == {"storeCode": "COOLBOX", "externalProductId": "2"}


def test_set_role(db, auth_emulator):
    auth_emulator.create_user(email="admin@precio.pe", password="precio2026")
    assert set_role(db, "Admin@Precio.pe ", "admin") == {"admin": True}
    assert set_role(db, "admin@precio.pe", "operator") == {"admin": True, "operator": True}
    assert set_role(db, "admin@precio.pe", "admin", remove=True) == {"operator": True}
    claims = auth_emulator.get_user_by_email("admin@precio.pe").custom_claims
    assert claims == {"operator": True}
    with pytest.raises(auth_emulator.UserNotFoundError):
        set_role(db, "nadie@precio.pe", "admin")


def test_status(db):
    seed_review(db)
    db.document("stores/PLAZAVEA").set({"name": "Plaza Vea", "scrapingEnabled": True, "scrapingIntervalMinutes": 720})
    report = collect(db, now=NOW + timedelta(hours=1))
    health = {s["code"]: s["health"] for s in report["stores"]}
    assert health == {"COOLBOX": OK, "PLAZAVEA": NEVER}
    assert report["pendingReview"] == 2 and report["unmatched"] == 1 and report["products"] == 2
    assert next(s for s in report["stores"] if s["code"] == "COOLBOX")["listings"] == 3


def test_backup_roundtrip(db, tmp_path):
    seed_review(db)
    db.document("users/ana").set({"email": "ana@correo.pe", "plan": "FREE"})
    db.document("users/ana/alerts/a1").set({"productId": "lenovo-slim3-r5", "targetPriceCents": 200000})
    db.document("storeProducts/COOLBOX__1/history/2026-11").set(
        {"month": "2026-11", "points": [{"t": NOW, "p": 229900, "a": "AVAILABLE", "s": None}]})

    catalog = export(db, tmp_path / "catalogo", include_users=False)
    assert catalog["includesPersonalData"] is False
    assert "users" not in catalog["documents"]
    assert catalog["documents"]["history"] == 1  # subcolecciones incluidas

    full = export(db, tmp_path / "completo", include_users=True)
    assert full["documents"]["users"] == 1 and full["documents"]["alerts"] == 1

    # Restaurar en una base vacía reproduce los mismos documentos (con tipos).
    original_history = db.document("storeProducts/COOLBOX__1/history/2026-11").get().to_dict()
    from tests_emulator.conftest import PROJECT, _delete
    import os
    _delete(f"http://{os.environ['FIRESTORE_EMULATOR_HOST']}/emulator/v1/projects/{PROJECT}/databases/(default)/documents")
    assert not db.document("users/ana").get().exists
    count = restore(db, tmp_path / "completo" / full["file"])
    assert count == full["total"]
    assert db.document("users/ana/alerts/a1").get().to_dict()["targetPriceCents"] == 200000
    assert db.document("storeProducts/COOLBOX__1/history/2026-11").get().to_dict() == original_history



def test_merge_products_and_migrate_user_tracking(db):
    seed_review(db)
    db.document("products/dup-a").set({"displayName": "Lavadora LG WT19BVTB", "categorySlug": "lavadoras",
                                       "status": "ACTIVE", "identifierKeys": ["GTIN:2001234567893"],
                                       "searchTokens": ["lg", "lavadora"], "summary": {}})
    db.document("products/dup-b").set({"displayName": "Lavadora LG 19kg WT19BVTB", "categorySlug": "lavadoras",
                                       "status": "ACTIVE", "identifierKeys": ["MPN:WT19BVTB"],
                                       "searchTokens": ["wt19bvtb"], "summary": {}})
    base = {"storeCode": "COOLBOX", "status": "ACTIVE", "availability": "AVAILABLE", "currency": "PEN",
            "lastCheckedAt": NOW, "missedRuns": 0, "matchStatus": "MATCHED_AUTO", "createdAt": NOW}
    db.document("storeProducts/A__1").set({**base, "productId": "dup-a", "currentPriceCents": 204900, "title": "a"})
    db.document("storeProducts/B__1").set({**base, "productId": "dup-b", "currentPriceCents": 154900, "title": "b",
                                           "possibleDuplicateOf": "dup-a"})
    db.document("users/ana/favorites/dup-b").set({"productId": "dup-b", "productName": "x"})
    db.document("users/ana/alerts/al1").set({"productId": "dup-b", "status": "ACTIVE", "targetPriceCents": 160000,
                                             "evaluatedAt": NOW})
    db.document("users/ana/wishlists/l1").set({"name": "Casa", "productIds": ["dup-b", "dup-a"]})

    assert [d["id"] for d in review.list_duplicates(db)] == ["B__1"]
    result = review.merge(db, "dup-a", "dup-b")
    assert result == {"listingsMoved": 1, "favorites": 1, "alerts": 1, "wishlists": 1}

    kept = db.document("products/dup-a").get().to_dict()
    assert set(kept["identifierKeys"]) == {"GTIN:2001234567893", "MPN:WT19BVTB"}
    assert kept["summary"]["minPriceCents"] == 154900  # ahora compara las dos ofertas
    removed = db.document("products/dup-b").get().to_dict()
    assert (removed["status"], removed["mergedInto"]) == ("MERGED", "dup-a")
    assert db.document("storeProducts/B__1").get().to_dict()["possibleDuplicateOf"] is None
    assert db.document("users/ana/favorites/dup-a").get().exists
    assert not db.document("users/ana/favorites/dup-b").get().exists
    assert db.document("users/ana/alerts/al1").get().to_dict()["productId"] == "dup-a"
    assert db.document("users/ana/wishlists/l1").get().to_dict()["productIds"] == ["dup-a"]
    with pytest.raises(review.ReviewError):
        review.merge(db, "dup-a", "dup-b")  # ya unificado
