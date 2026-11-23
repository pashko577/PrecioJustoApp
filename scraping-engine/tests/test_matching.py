from datetime import datetime, timedelta, timezone

from app.admin.stores import load_stores, store_document
from app.catalog import NO_PRICE_SORT_VALUE
from app.matching.scoring import Candidate, Listing, blocking_reason, decide, score
from app.postprocess.summary import compute_summary

NV3_1TB = Candidate(product_id="nv3-1tb", name="Kingston NV3 1TB SSD NVMe PCIe 4.0", brand="Kingston", model="NV3")
NV3_2TB = Candidate(product_id="nv3-2tb", name="Kingston NV3 2TB SSD NVMe PCIe 4.0", brand="Kingston", model="NV3")
A400 = Candidate(product_id="a400-960", name="Kingston A400 960GB SSD SATA", brand="Kingston", model="A400")


# ---------- Reglas bloqueantes (8.3) ----------

def test_different_capacity_is_blocked():
    listing = Listing(title="Disco sólido Kingston NV3 de 2000 GB", brand="Kingston")
    assert "capacidad" in blocking_reason(listing, NV3_1TB)
    assert blocking_reason(listing, NV3_2TB) is None


def test_refurbished_never_matches_new():
    listing = Listing(title="Kingston NV3 1TB", brand="Kingston", condition="REFURBISHED")
    assert "condición" in blocking_reason(listing, NV3_1TB)


def test_pack_vs_unit_blocked():
    listing = Listing(title="Pack x2 Kingston NV3 1TB", brand="Kingston")
    assert "paquete" in blocking_reason(listing, NV3_1TB)


def test_color_variants_blocked():
    black = Candidate(product_id="xs-negro", name="Kingston XS1000 1TB negro", brand="Kingston", model="XS1000")
    assert "color" in blocking_reason(Listing(title="Kingston XS1000 1TB rojo", brand="Kingston"), black)
    assert blocking_reason(Listing(title="Kingston XS1000 1TB negro", brand="Kingston"), black) is None


def test_different_gtin_blocked():
    with_gtin = Candidate(product_id="x", name="Kingston NV3 1TB", brand="Kingston", model="NV3", gtins={"1111111111116"})
    assert "código" in blocking_reason(Listing(title="Kingston NV3 1TB", brand="Kingston", gtin="2001234567893"), with_gtin)


# ---------- Puntuación y decisión (8.4) ----------

def test_same_product_different_titles_scores_high():
    for title in ["Kingston SSD NV3 1TB", "SSD Kingston 1TB PCIe 4.0 NV3", "Disco sólido Kingston NV3 de 1000 GB NVMe PCIe 4.0"]:
        s = score(Listing(title=title, brand="Kingston"), NV3_1TB)
        assert s >= 75, (title, s)


def test_wrong_model_scores_low():
    assert score(Listing(title="Kingston A400 1TB SSD", brand="Kingston"), NV3_1TB) < 75


def test_different_product_type_scores_low():
    # Mismo modelo y capacidad, pero características contradictorias (externo USB vs NVMe).
    assert score(Listing(title="Kingston NV3 1TB SATA externo USB", brand="Kingston"), NV3_1TB) < 75


def test_missing_capacity_goes_to_review_not_auto():
    d = decide(Listing(title="Kingston NV3", brand="Kingston"), [NV3_1TB])
    assert d.status == "PENDING_REVIEW"


def test_decide_prefers_gtin():
    with_gtin = Candidate(product_id="g", name="Otro nombre", brand="Kingston", gtins={"2001234567893"})
    d = decide(Listing(title="Kingston NV3 1TB", brand="Kingston", gtin="2001234567893"), [NV3_1TB, with_gtin])
    assert (d.product_id, d.status, d.score) == ("g", "MATCHED_AUTO", 100)


def test_decide_never_picks_blocked_candidate():
    d = decide(Listing(title="Kingston NV3 2TB SSD NVMe PCIe 4.0", brand="Kingston"), [NV3_1TB])
    assert d.status == "UNMATCHED" and d.product_id is None


def test_decide_thresholds():
    exact = decide(Listing(title="Kingston NV3 1TB SSD NVMe PCIe 4.0", brand="Kingston", model="NV3"), [NV3_1TB, A400])
    assert exact.status == "MATCHED_AUTO" and exact.product_id == "nv3-1tb"
    nothing = decide(Listing(title="Samsung 990 Pro 1TB", brand="Samsung"), [NV3_1TB, A400])
    assert nothing.status == "UNMATCHED"


# ---------- Resumen de precios (RN-01, RN-02) ----------

NOW = datetime(2026, 11, 23, 12, tzinfo=timezone.utc)


def offer(store, price, availability="AVAILABLE", hours=1, status="ACTIVE"):
    return {"storeCode": store, "currentPriceCents": price, "availability": availability,
            "lastCheckedAt": NOW - timedelta(hours=hours), "status": status, "currency": "PEN"}


def test_summary_uses_only_fresh_available_active_offers():
    summary = compute_summary([
        offer("A", 30000),
        offer("B", 10000, hours=48),               # vieja
        offer("C", 5000, availability="OUT_OF_STOCK"),
        offer("D", 1000, status="GONE"),           # retirada: no cuenta
    ], {"A": {"freshnessMinutes": 720}, "B": {"freshnessMinutes": 720}, "C": {"freshnessMinutes": 720}}, now=NOW)
    assert summary["minPriceCents"] == 30000 and summary["minPriceStoreCode"] == "A"
    assert summary["sortPriceCents"] == 30000
    assert summary["offerCount"] == 3 and summary["verifiedOfferCount"] == 1
    assert summary["maxPriceCents"] == 30000


def test_summary_respects_store_freshness():
    summary = compute_summary([offer("A", 30000, hours=5)], {"A": {"freshnessMinutes": 240}}, now=NOW)  # 4 h
    assert summary["minPriceCents"] is None and summary["sortPriceCents"] == NO_PRICE_SORT_VALUE


def test_summary_without_offers():
    summary = compute_summary([], {}, now=NOW)
    assert summary["offerCount"] == 0 and summary["sortPriceCents"] == NO_PRICE_SORT_VALUE


# ---------- Registro de tiendas (7.7) ----------

def test_enabled_stores_have_review():
    stores = load_stores()
    coolbox = next(s for s in stores if s["code"] == "COOLBOX")
    doc = store_document(coolbox)
    assert doc["scrapingEnabled"] and doc["status"] == "ACTIVE"
    assert doc["termsReviewedAt"].year == 2026
    assert "RASH PERU" in doc["reviewNotes"]


def test_store_without_review_cannot_be_enabled(tmp_path):
    import json

    import pytest
    f = tmp_path / "s.json"
    f.write_text(json.dumps([{"code": "X", "name": "X", "baseUrl": "https://x.pe", "scrapingEnabled": True}]), "utf-8")
    with pytest.raises(ValueError, match="evaluación"):
        load_stores(f)


def test_joined_versions_match_separated():
    # Título real de Coolbox: "PCIE4.0" junto vs. "PCIe 4.0" separado en el catálogo.
    listing = Listing(title="Unidad de estado sólido SSD Kingston NV3 1000GB M.2 PCIE4.0 NVME", brand="Kingston")
    assert score(listing, NV3_1TB) >= 90


def test_decide_by_manufacturer_code():
    mac = Candidate(product_id="mac", name="MacBook Air 13 M4", brand="Apple", model="MacBook Air", mpns={"MDHE4E/A"})
    d = decide(Listing(title="Apple MacBook Air 13 pulgadas", brand="Apple", mpn="MDHE4E/A"), [mac])
    assert (d.product_id, d.status, d.reason) == ("mac", "MATCHED_AUTO", "mismo código de fabricante")


def test_different_refresh_rate_is_blocked():
    g5 = Candidate(product_id="g5-165", name="Monitor Samsung Odyssey G5 27 pulgadas 165Hz", brand="Samsung", model="Odyssey G5")
    listing = Listing(title="Monitor gamer Samsung Odyssey G5 G50F, 27 QHD Fast IPS, 180Hz", brand="Samsung")
    assert "capacidad" in blocking_reason(listing, g5) or "distinta" in blocking_reason(listing, g5)


def test_enabled_spiders_and_registry_agree():
    from app.admin.stores import enabled_spiders
    from app.spiders.vtex.registry import SPIDERS
    enabled = enabled_spiders()
    assert "coolbox" in enabled
    assert set(enabled) <= set(SPIDERS) | {"demo_store"}


def test_store_with_unknown_category_rejected(tmp_path):
    import json

    import pytest
    f = tmp_path / "s.json"
    f.write_text(json.dumps([{"code": "X", "name": "X", "baseUrl": "https://x.pe", "platform": "VTEX",
                              "spider": "x", "vtexCategories": {"/1/": "no-existe"}}]), "utf-8")
    with pytest.raises(ValueError, match="categorías desconocidas"):
        load_stores(f)


# ---------- Verificación por corrida completa de la tienda ----------

def test_unchanged_offer_is_verified_by_store_run():
    from app.postprocess.summary import effective_checked_at
    old = offer("A", 30000, hours=48)                      # escrita hace 2 días, sin cambios desde entonces
    store = {"freshnessMinutes": 720, "lastCompleteRunAt": NOW - timedelta(hours=1)}
    assert effective_checked_at(old, store) == NOW - timedelta(hours=1)
    summary = compute_summary([old], {"A": store}, now=NOW)
    assert summary["minPriceCents"] == 30000               # sigue vigente gracias a la corrida de la tienda


def test_missing_offer_is_not_verified_by_store_run():
    from app.postprocess.summary import effective_checked_at
    missing = offer("A", 30000, hours=48) | {"missedRuns": 1}   # no apareció en la última corrida
    store = {"freshnessMinutes": 720, "lastCompleteRunAt": NOW - timedelta(hours=1)}
    assert effective_checked_at(missing, store) == NOW - timedelta(hours=48)
    assert compute_summary([missing], {"A": store}, now=NOW)["minPriceCents"] is None


def test_needs_write_only_on_material_changes():
    from app.pipelines.firestore import needs_write
    base = {"status": "ACTIVE", "missedRuns": 0, "currentPriceCents": 100, "availability": "AVAILABLE",
            "title": "X", "productId": "p", "matchStatus": "MATCHED_AUTO"}
    assert needs_write(None, base)
    assert not needs_write(base, dict(base))
    assert needs_write(base, base | {"currentPriceCents": 90})
    assert needs_write(base, base | {"title": "Y"})
    assert needs_write(base | {"missedRuns": 1}, base)       # reapareció: reiniciar missedRuns
    assert needs_write(base | {"status": "GONE"}, base)
