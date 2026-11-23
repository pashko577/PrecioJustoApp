"""Registra o actualiza las tiendas y su evaluación de extracción (`app/data/stores.json`).

Uso:
    python -m app.admin.stores                 # emulador
    python -m app.admin.stores --prod --yes    # proyecto real
    python -m app.admin.stores --list-enabled  # spiders activos en JSON (lo usa el workflow)
"""

from __future__ import annotations

import argparse
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

from firebase_admin import firestore

from app.admin.target import add_target_args, resolve_db
from app.catalog import flatten_categories

STORES_FILE = Path(__file__).resolve().parents[1] / "data" / "stores.json"
REQUIRED_REVIEW_FIELDS = ("reviewedAt", "robotsTxt", "terms", "conclusion")


def load_stores(path: Path = STORES_FILE) -> list[dict]:
    stores = json.loads(path.read_text("utf-8"))
    valid_categories = {c["slug"] for c in flatten_categories()}
    codes = [s["code"] for s in stores]
    if len(codes) != len(set(codes)):
        raise ValueError("Códigos de tienda duplicados en stores.json")
    for store in stores:
        unknown = set((store.get("vtexCategories") or {}).values()) - valid_categories
        if unknown:
            raise ValueError(f"{store['code']}: categorías desconocidas {sorted(unknown)}")
        if store.get("scrapingEnabled") and store.get("platform") == "VTEX" and not store.get("vtexCategories"):
            raise ValueError(f"{store['code']}: tienda VTEX activa sin vtexCategories")
        review = store.get("review") or {}
        missing = [f for f in REQUIRED_REVIEW_FIELDS if not review.get(f)]
        if store.get("scrapingEnabled") and missing:
            # Sección 7.7: ninguna tienda se activa sin su evaluación registrada.
            raise ValueError(f"{store['code']}: falta la evaluación ({', '.join(missing)}) para activar la extracción.")
    return stores


def store_document(store: dict) -> dict:
    review = store.get("review") or {}
    reviewed = datetime.fromisoformat(review["reviewedAt"]).replace(tzinfo=timezone.utc) if review.get("reviewedAt") else None
    return {
        "name": store["name"],
        "baseUrl": store["baseUrl"],
        "platform": store.get("platform"),
        "spider": store.get("spider"),
        "countryCode": "PE",
        "status": "ACTIVE" if store.get("scrapingEnabled") else "UNDER_REVIEW",
        "scrapingEnabled": bool(store.get("scrapingEnabled")),
        "scrapingIntervalMinutes": store.get("scrapingIntervalMinutes", 360),
        "freshnessMinutes": store.get("freshnessMinutes", 720),
        "termsReviewedAt": reviewed,
        "robotsReviewedAt": reviewed,
        "reviewNotes": " | ".join(review.get(k, "") for k in ("robotsTxt", "terms", "conclusion", "notes") if review.get(k)),
        "updatedAt": firestore.SERVER_TIMESTAMP,
    }


def enabled_spiders(stores: list[dict] | None = None) -> list[str]:
    """Spiders de las tiendas activas (con evaluación registrada)."""
    return [s["spider"] for s in (stores if stores is not None else load_stores())
            if s.get("scrapingEnabled") and s.get("spider")]


def upload_stores(db, stores: list[dict]) -> int:
    batch = db.batch()
    for store in stores:
        batch.set(db.collection("stores").document(store["code"]), store_document(store), merge=True)
    batch.commit()
    return len(stores)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    add_target_args(parser)
    parser.add_argument("--list-enabled", action="store_true", help="Imprime los spiders activos (JSON) y sale.")
    args = parser.parse_args(argv)
    stores = load_stores()
    if args.list_enabled:
        print(json.dumps(enabled_spiders(stores)))
        return 0
    count = upload_stores(resolve_db(args), stores)
    print(f"Tiendas registradas: {count}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
