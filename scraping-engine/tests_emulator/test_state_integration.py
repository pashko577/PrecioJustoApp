"""Copia de trabajo del motor (app/state.py) en un ciclo completo contra el emulador."""

import json
import logging
from datetime import datetime, timezone
from types import SimpleNamespace

from firebase_admin import firestore

from app.models.offer import ScrapedOffer


def _offer(ext: str, title: str, mpn: str | None) -> ScrapedOffer:
    return ScrapedOffer(
        store_code="COOLBOX", external_product_id=ext, title=title, price_cents=200_000,
        product_url=f"https://example.com/{ext}", availability="AVAILABLE", brand="Sony", model=mpn,
        identifiers={"MPN": mpn} if mpn else {}, category_hint="consolas",
    )


def _run(offers):
    from app.pipelines.firestore import FirestorePipeline

    spider = SimpleNamespace(store_code="COOLBOX", logger=logging.getLogger("test"), job_errors=[], max_pages=None)
    pipeline = FirestorePipeline()
    pipeline.crawler = SimpleNamespace(spider=spider, stats=SimpleNamespace(get_value=lambda _k, d=0: d))
    pipeline.open_spider(spider)
    for offer in offers:
        pipeline.process_item(offer, spider)
    pipeline.close_spider(spider)
    return pipeline


def test_engine_state_cycle(db, tmp_path, monkeypatch):
    from app.export.catalog import main
    from app.state import EngineState

    db.document("stores/COOLBOX").set({"name": "Coolbox", "freshnessMinutes": 1440, "scrapingEnabled": True})
    out, state_path, catalog = tmp_path / "out", tmp_path / "engine-state.json.gz", tmp_path / "catalog.json"
    monkeypatch.setenv("ENGINE_STATE_OUT", str(out))
    ps5 = _offer("1", "Consola Sony PlayStation 5 Slim CFI-2015", "CFI2015")
    other = _offer("2", "Silla gamer reclinable negra", None)

    # 1) Sin copia: lee Firestore como antes y deja las publicaciones finales de la tienda.
    first = _run([ps5, other])
    assert not first.state_used
    assert (out / "COOLBOX.json.gz").exists()
    statuses = {k: v.get("matchStatus") for k, v in first.existing.items()}
    assert statuses == {"COOLBOX__1": "MATCHED_AUTO", "COOLBOX__2": "UNMATCHED"}

    # 2) Job final: copia completa (no había anterior) y catálogo desde ella.
    assert main(["--out", str(catalog), "--state", str(state_path), "--store-states", str(out)]) == 0
    state = EngineState.load(state_path)
    assert set(state.listings) == {"COOLBOX__1", "COOLBOX__2"} and len(state.products) == 1
    assert [o["id"] for o in json.loads(catalog.read_text("utf-8"))["offers"]] == ["COOLBOX__1"]

    # Decisión manual entre corridas: la siguiente la ve por `updatedAt`.
    db.document("storeProducts/COOLBOX__1").update({"matchStatus": "MATCHED_MANUAL",
                                                    "updatedAt": datetime.now(timezone.utc)})

    # 3) Con copia: casi sin lecturas y sin cargar categorías desde Firestore.
    monkeypatch.setenv("ENGINE_STATE", str(state_path))
    second = _run([ps5])  # la silla ya no aparece: estaba sin asociar, se borra
    assert second.state_used
    assert second.matcher.reads == 0
    assert second.existing["COOLBOX__1"]["matchStatus"] == "MATCHED_MANUAL"
    assert "COOLBOX__2" not in second.existing
    assert db.document("storeProducts/COOLBOX__2").get().exists is False

    # 4) Copia incremental: toma las publicaciones finales de la tienda (incluye el borrado).
    assert main(["--out", str(catalog), "--state", str(state_path), "--store-states", str(out)]) == 0
    assert set(EngineState.load(state_path).listings) == {"COOLBOX__1"}


def test_listing_written_this_run_keeps_resolved_timestamps(db, tmp_path, monkeypatch):
    from app.state import EngineState, load_store_listings

    db.document("stores/COOLBOX").set({"name": "Coolbox", "scrapingEnabled": True})
    monkeypatch.setenv("ENGINE_STATE_OUT", str(tmp_path / "out"))
    _run([_offer("1", "Consola Sony PlayStation 5 Slim CFI-2015", "CFI2015")])
    saved = load_store_listings(tmp_path / "out")["COOLBOX"]["COOLBOX__1"]
    assert isinstance(saved["updatedAt"], datetime)  # no queda el marcador SERVER_TIMESTAMP
    assert saved["updatedAt"] is not firestore.SERVER_TIMESTAMP
    EngineState(datetime.now(timezone.utc), {}, {"COOLBOX__1": saved}).save(tmp_path / "s.json.gz")
