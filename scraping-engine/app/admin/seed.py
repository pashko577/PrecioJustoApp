"""Carga datos de ejemplo en el EMULADOR de Firestore.

- Árbol real de categorías (`app/data/categories.json`).
- Catálogo de ejemplo sin precios (`app/data/sample_products.json`).
- 4 productos con ofertas FICTICIAS de dos tiendas demo, para probar la comparación.

Uso (con los emuladores levantados):
    PowerShell: $env:FIRESTORE_EMULATOR_HOST="127.0.0.1:8085"
    python -m app.admin.seed

Por seguridad, se niega a ejecutarse contra un proyecto real.
"""

from __future__ import annotations

import sys
from datetime import datetime, timedelta, timezone

from firebase_admin import firestore

from app.admin.categories import upload_categories
from app.admin.import_products import load_products, write_products
from app.admin.stores import load_stores, upload_stores
from app.catalog import (
    CATEGORIES_FILE,
    NO_PRICE_SORT_VALUE,
    ProductInput,
    build_product_doc,
    flatten_categories,
)
from app.firebase_client import get_db, using_emulator

NOW = datetime.now(timezone.utc)
FRESHNESS_MINUTES = 12 * 60
SAMPLE_PRODUCTS_FILE = CATEGORIES_FILE.parent / "sample_products.json"

STORES = [
    {"code": "DEMO_STORE", "name": "Tienda Demo", "baseUrl": "https://demo.example.com"},
    {"code": "DEMO_STORE_B", "name": "Tienda Demo B", "baseUrl": "https://demo-b.example.com"},
]

# (producto, [(tienda, sku, precio_céntimos, disponibilidad, envío, horas_desde_verificación)])
DEMO_OFFERS: list[tuple[ProductInput, list[tuple]]] = [
    (ProductInput(id="kingston-nv3-1tb", category="ssd", brand="Kingston", model="NV3",
                  name="Kingston NV3 1TB SSD NVMe PCIe 4.0",
                  attributes={"capacidad": "1 TB", "interfaz": "PCIe 4.0"},
                  identifiers={"EAN": ["2001234567893"]}),  # EAN FICTICIO (igual al de la página demo)
     [("DEMO_STORE", "KNV3-1TB", 24990, "AVAILABLE", 1000, 2),
      ("DEMO_STORE_B", "B-778", 25990, "AVAILABLE", None, 3)]),
    (ProductInput(id="samsung-990-evo-plus-1tb", category="ssd", brand="Samsung", model="990 EVO Plus",
                  name="Samsung 990 EVO Plus 1TB SSD NVMe",
                  attributes={"capacidad": "1 TB", "interfaz": "PCIe 4.0"}),
     [("DEMO_STORE", "SAM-990-1TB", 38900, "PREORDER", 0, 2),
      ("DEMO_STORE_B", "B-912", 36990, "AVAILABLE", 1500, 30)]),  # desactualizada (> vigencia)
    (ProductInput(id="kingston-fury-beast-16gb-ddr5", category="memorias-ram", brand="Kingston", model="Fury Beast",
                  name="Kingston Fury Beast 16GB DDR5 5600MHz",
                  attributes={"capacidad": "16 GB", "tipo": "DDR5", "velocidad": "5600 MHz"}),
     [("DEMO_STORE_B", "B-301", 21990, "AVAILABLE", None, 1)]),
    (ProductInput(id="lg-ultragear-27gs60f", category="monitores", brand="LG", model="27GS60F",
                  name="Monitor LG UltraGear 27 pulgadas 180Hz",
                  attributes={"tamano": "27", "frecuencia": "180 Hz"}),
     [("DEMO_STORE", "LG-27GS60F", 69900, "OUT_OF_STOCK", None, 4)]),
]


def compute_summary(offers: list[tuple]) -> dict:
    """Resumen de precios (RN-01, RN-02): mínimo solo entre ofertas vigentes y disponibles."""
    verified = [
        (price, store)
        for store, _, price, availability, _, hours in offers
        if availability == "AVAILABLE" and timedelta(hours=hours) <= timedelta(minutes=FRESHNESS_MINUTES)
    ]
    best = min(verified) if verified else None
    return {
        "currency": "PEN",
        "minPriceCents": best[0] if best else None,
        "minPriceStoreCode": best[1] if best else None,
        "maxPriceCents": max(o[2] for o in offers),
        "sortPriceCents": best[0] if best else NO_PRICE_SORT_VALUE,
        "offerCount": len(offers),
        "verifiedOfferCount": len(verified),
        "lastCheckedAt": max(NOW - timedelta(hours=o[5]) for o in offers),
    }


def seed(db) -> None:
    categories = flatten_categories()
    upload_categories(db, categories)
    upload_stores(db, load_stores())  # tiendas reales registradas (con su evaluación)
    valid = {c["slug"] for c in categories}
    write_products(db, load_products(SAMPLE_PRODUCTS_FILE, valid))

    batch = db.batch()
    batch.set(db.document("config/app"), {
        "defaultFreshnessMinutes": FRESHNESS_MINUTES,
        "freePlanLimits": {"favorites": 50, "alerts": 5, "wishlists": 3},
        "minAppVersion": "0.1.0",
    })
    for s in STORES:
        batch.set(db.document(f"stores/{s['code']}"), {
            "name": s["name"], "baseUrl": s["baseUrl"], "countryCode": "PE",
            "status": "ACTIVE", "scrapingEnabled": False, "scrapingIntervalMinutes": 360,
            "freshnessMinutes": FRESHNESS_MINUTES, "lastRunAt": None, "lastRunStatus": None,
            "termsReviewedAt": None, "robotsReviewedAt": None,
            "reviewNotes": "Tienda ficticia para desarrollo.",
            "createdAt": firestore.SERVER_TIMESTAMP, "updatedAt": firestore.SERVER_TIMESTAMP,
        })
    store_names = {s["code"]: s["name"] for s in STORES}

    for product, offers in DEMO_OFFERS:
        pid, data = build_product_doc(product, valid)
        for store, sku, price, availability, shipping, hours_ago in offers:
            checked = NOW - timedelta(hours=hours_ago)
            sp_id = f"{store}__{sku}"
            batch.set(db.document(f"storeProducts/{sp_id}"), {
                "storeCode": store, "storeName": store_names[store], "externalProductId": sku,
                "productId": pid, "variantId": None, "title": data["displayName"],
                "productUrl": f"https://demo.example.com/p/{sku}", "imageUrl": None,
                "sellerName": store_names[store], "condition": "NEW",
                "matchStatus": "MATCHED_MANUAL", "matchScore": 100,
                "currentPriceCents": price, "previousPriceCents": price + 2000,
                "currentShippingCents": shipping, "currency": "PEN", "availability": availability,
                "lastCheckedAt": checked, "lastChangedAt": checked - timedelta(days=3),
                "status": "ACTIVE", "missedRuns": 0,
                "createdAt": firestore.SERVER_TIMESTAMP, "updatedAt": firestore.SERVER_TIMESTAMP,
            })
            month = checked.strftime("%Y-%m")
            batch.set(db.document(f"storeProducts/{sp_id}/history/{month}"), {
                "month": month, "lastCheckedAt": checked,
                "points": [
                    {"t": checked - timedelta(days=10), "p": price + 3000, "a": "AVAILABLE", "s": shipping},
                    {"t": checked - timedelta(days=3), "p": price + 2000, "a": "AVAILABLE", "s": shipping},
                    {"t": checked, "p": price, "a": availability, "s": shipping},
                ],
            })
        batch.set(db.document(f"products/{pid}"), {
            **data,
            "summary": compute_summary(offers),
            "createdAt": firestore.SERVER_TIMESTAMP,
            "updatedAt": firestore.SERVER_TIMESTAMP,
        })
    batch.commit()


def main() -> int:
    if not using_emulator():
        print("ERROR: define FIRESTORE_EMULATOR_HOST. Este script solo se ejecuta contra el emulador.")
        return 1
    seed(get_db())
    sample = len(load_products(SAMPLE_PRODUCTS_FILE, {c["slug"] for c in flatten_categories()}))
    print(
        f"Datos de ejemplo cargados: {len(flatten_categories())} categorías, {len(STORES)} tiendas, "
        f"{sample + len(DEMO_OFFERS)} productos ({len(DEMO_OFFERS)} con ofertas)."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
