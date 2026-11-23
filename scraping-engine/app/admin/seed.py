"""Carga datos de ejemplo FICTICIOS en el emulador de Firestore.

Uso (con los emuladores levantados):
    set FIRESTORE_EMULATOR_HOST=127.0.0.1:8085      (PowerShell: $env:FIRESTORE_EMULATOR_HOST="127.0.0.1:8085")
    python -m app.admin.seed

Por seguridad, se niega a ejecutarse contra un proyecto real.
"""

from __future__ import annotations

import sys
from datetime import datetime, timedelta, timezone

from firebase_admin import firestore

from app.firebase_client import get_db, using_emulator
from app.normalizers.text import normalize_text, search_tokens

NOW = datetime.now(timezone.utc)

CATEGORIES = [
    {"slug": "tecnologia", "name": "Tecnología", "parentSlug": None, "order": 1},
    {"slug": "computacion", "name": "Computación", "parentSlug": "tecnologia", "order": 2},
    {"slug": "ssd", "name": "Discos SSD", "parentSlug": "computacion", "order": 3},
    {"slug": "memorias-ram", "name": "Memorias RAM", "parentSlug": "computacion", "order": 4},
    {"slug": "monitores", "name": "Monitores", "parentSlug": "tecnologia", "order": 5},
]

STORES = [
    {"code": "DEMO_STORE", "name": "Tienda Demo", "baseUrl": "https://demo.example.com"},
    {"code": "DEMO_STORE_B", "name": "Tienda Demo B", "baseUrl": "https://demo-b.example.com"},
]

# (id, categoría, marca, modelo, nombre, atributos, [(tienda, sku, precio_céntimos, disponibilidad, envío, horas_desde_verificación)])
PRODUCTS = [
    ("kingston-nv3-1tb", "ssd", "Kingston", "NV3", "Kingston NV3 1TB SSD NVMe PCIe 4.0",
     {"capacity": "1tb", "interface": "pcie 4.0"},
     [("DEMO_STORE", "KNV3-1TB", 24990, "AVAILABLE", 1000, 2),
      ("DEMO_STORE_B", "B-778", 25990, "AVAILABLE", None, 3)]),
    ("samsung-990-evo-plus-1tb", "ssd", "Samsung", "990 EVO Plus", "Samsung 990 EVO Plus 1TB SSD NVMe",
     {"capacity": "1tb", "interface": "pcie 4.0"},
     [("DEMO_STORE", "SAM-990-1TB", 38900, "PREORDER", 0, 2),
      ("DEMO_STORE_B", "B-912", 36990, "AVAILABLE", 1500, 30)]),  # desactualizada (> vigencia)
    ("kingston-fury-beast-16gb-ddr5", "memorias-ram", "Kingston", "Fury Beast", "Kingston Fury Beast 16GB DDR5 5600MHz",
     {"capacity": "16gb", "type": "ddr5", "speed": "5600mhz"},
     [("DEMO_STORE_B", "B-301", 21990, "AVAILABLE", None, 1)]),
    ("lg-27-ultragear-27gs60f", "monitores", "LG", "27GS60F", "Monitor LG UltraGear 27 pulgadas 180Hz",
     {"size": "27in", "refresh": "180hz"},
     [("DEMO_STORE", "LG-27GS60F", 69900, "OUT_OF_STOCK", None, 4)]),
]

FRESHNESS_MINUTES = 12 * 60


def seed(db) -> None:
    batch = db.batch()

    batch.set(db.document("config/app"), {
        "defaultFreshnessMinutes": FRESHNESS_MINUTES,
        "freePlanLimits": {"favorites": 50, "alerts": 5, "wishlists": 3},
        "minAppVersion": "0.1.0",
    })

    for c in CATEGORIES:
        batch.set(db.document(f"categories/{c['slug']}"), {**c, "description": "", "status": "ACTIVE"})

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

    for pid, cat, brand, model, name, attrs, offers in PRODUCTS:
        verified = []
        for store, sku, price, availability, shipping, hours_ago in offers:
            checked = NOW - timedelta(hours=hours_ago)
            sp_id = f"{store}__{sku}"
            batch.set(db.document(f"storeProducts/{sp_id}"), {
                "storeCode": store, "storeName": store_names[store], "externalProductId": sku,
                "productId": pid, "variantId": None, "title": name,
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
            is_fresh = (NOW - checked) <= timedelta(minutes=FRESHNESS_MINUTES)
            if is_fresh and availability == "AVAILABLE":
                verified.append((price, store))

        all_prices = [o[2] for o in offers]
        best = min(verified) if verified else None
        batch.set(db.document(f"products/{pid}"), {
            "categorySlug": cat, "brand": brand, "model": model,
            "normalizedName": normalize_text(name), "displayName": name,
            "description": "", "imageUrl": None, "condition": "NEW", "status": "ACTIVE",
            "identifiers": {}, "identifierKeys": [], "attributes": attrs, "variants": [],
            "searchTokens": search_tokens(name, brand, model),
            "summary": {
                "currency": "PEN",
                "minPriceCents": best[0] if best else None,
                "minPriceStoreCode": best[1] if best else None,
                "maxPriceCents": max(all_prices),
                "offerCount": len(offers),
                "verifiedOfferCount": len(verified),
                "lastCheckedAt": max(NOW - timedelta(hours=o[5]) for o in offers),
            },
            "createdAt": firestore.SERVER_TIMESTAMP, "updatedAt": firestore.SERVER_TIMESTAMP,
        })

    batch.commit()


def main() -> int:
    if not using_emulator():
        print("ERROR: define FIRESTORE_EMULATOR_HOST. Este script solo se ejecuta contra el emulador.")
        return 1
    seed(get_db())
    print(f"Datos de ejemplo cargados: {len(CATEGORIES)} categorías, {len(STORES)} tiendas, {len(PRODUCTS)} productos.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
