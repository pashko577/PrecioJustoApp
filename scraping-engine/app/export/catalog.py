"""Catálogo público en un archivo (`catalog.json`) para la app: 0 lecturas de Firestore por usuario.

La app descarga este archivo (publicado en GitHub Pages) una vez cada pocas horas, lo guarda en
el celular y navega, busca y compara desde ahí. Firestore queda solo para los datos de cada
cuenta (favoritos, listas, alertas) y el historial de precios.

Exportación incremental: parte del catálogo publicado y solo lee de Firestore los productos y
las publicaciones con `updatedAt` posterior a esa versión (más un margen). Sin catálogo previo, o
con `--full` (una vez por semana), lo arma completo.

Uso:
    python -m app.export.catalog --out dist/catalog.json --previous-url https://.../catalog.json
    python -m app.export.catalog --out dist/catalog.json --full --prod --yes
"""

from __future__ import annotations

import argparse
import gzip
import json
import sys
import urllib.request
from datetime import datetime, timedelta, timezone
from pathlib import Path

from google.cloud.firestore_v1.base_query import FieldFilter

from app.admin.target import add_target_args, resolve_db
from app.catalog import flatten_categories
from app.postprocess.summary import SHOWN_MATCH_STATUSES
from app.quota import QuotaTracker
from app.state import EngineState, build_state, load_store_listings

FORMAT_VERSION = 1
# Tope diario de lecturas del proyecto que la exportación no debe pasar (el plan gratuito da 50 000;
# con el catálogo local la app casi no lee Firestore, pero se deja margen).
PROJECT_DAILY_READS_CAP = 47_000
# Margen ante relojes desfasados y escrituras en curso durante la exportación anterior.
INCREMENTAL_MARGIN = timedelta(minutes=30)
SUMMARY_FIELDS = ("minPriceCents", "minPriceStoreCode", "maxPriceCents", "sortPriceCents", "offerCount",
                  "storeCount", "verifiedOfferCount", "lastCheckedAt", "currency", "priceDropFromCents", "priceDropPercent",
                  "priceDroppedAt")


def _iso(value):
    """Fechas como texto ISO en UTC; el resto igual."""
    if isinstance(value, datetime):
        if value.tzinfo is None:
            value = value.replace(tzinfo=timezone.utc)
        return value.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")
    return value


def _compact(d: dict) -> dict:
    """Sin campos vacíos: el archivo pesa menos y la app trata «ausente» como «nulo»."""
    return {k: _iso(v) for k, v in d.items() if v not in (None, "", [], {})}


def product_entry(pid: str, d: dict) -> dict | None:
    status = d.get("status", "ACTIVE")
    if status == "MERGED" and d.get("mergedInto"):
        return {"id": pid, "status": "MERGED", "mergedInto": d["mergedInto"]}  # para redirigir enlaces
    if status != "ACTIVE":
        return None
    summary = d.get("summary") or {}
    return _compact({
        "id": pid,
        "name": d.get("displayName") or d.get("normalizedName") or pid,
        "brand": d.get("brand"),
        "categorySlug": d.get("categorySlug"),
        "model": d.get("model"),
        "imageUrl": d.get("imageUrl"),
        "identifiers": d.get("identifiers"),
        "summary": _compact({k: summary.get(k) for k in SUMMARY_FIELDS}),
    })


def offer_entry(oid: str, d: dict) -> dict | None:
    """Solo publicaciones vigentes con asociación confirmada (las que la app muestra)."""
    if (d.get("status", "ACTIVE") != "ACTIVE" or not d.get("productId")
            or d.get("matchStatus", "MATCHED_AUTO") not in SHOWN_MATCH_STATUSES):
        return None
    return _compact({
        "id": oid,
        "productId": d["productId"],
        "storeCode": d.get("storeCode"),
        "storeName": d.get("storeName"),
        "title": d.get("title"),
        "productUrl": d.get("productUrl"),
        "priceCents": d.get("currentPriceCents"),
        "previousPriceCents": d.get("previousPriceCents"),
        "shippingCents": d.get("currentShippingCents"),
        "availability": d.get("availability"),
        "currency": d.get("currency"),
        "sellerName": d.get("sellerName"),
        "lastCheckedAt": d.get("lastCheckedAt"),
        "lastChangedAt": d.get("lastChangedAt"),
        "missedRuns": d.get("missedRuns") or None,
    })


def store_entry(code: str, d: dict) -> dict:
    return _compact({
        "code": code,
        "name": d.get("name"),
        "freshnessMinutes": d.get("freshnessMinutes"),
        "lastCompleteRunAt": d.get("lastCompleteRunAt"),
        "active": bool(d.get("scrapingEnabled", True)),
    })


def load_previous(url: str | None, path: Path | None = None) -> dict | None:
    """Catálogo publicado (None si no existe o no es de este formato)."""
    try:
        if path and path.exists():
            raw = path.read_bytes()
        elif url:
            req = urllib.request.Request(url, headers={"User-Agent": "CompraMejorExport/1.0",
                                                       "Accept-Encoding": "gzip"})
            with urllib.request.urlopen(req, timeout=30) as resp:
                raw = resp.read()
                if resp.headers.get("Content-Encoding") == "gzip":
                    raw = gzip.decompress(raw)
        else:
            return None
        data = json.loads(raw)
    except Exception as exc:  # primera vez, sitio caído o archivo dañado: exportación completa
        print(f"Sin catálogo previo utilizable ({type(exc).__name__}): se exporta completo.")
        return None
    return data if data.get("version") == FORMAT_VERSION else None


def _changed(db, collection: str, since: datetime | None):
    query = db.collection(collection)
    if since is not None:
        query = query.where(filter=FieldFilter("updatedAt", ">", since))
    return query.stream()


def estimate_reads(db, previous: dict | None) -> int:
    """Lecturas que costará exportar (contar cuesta 1 lectura por cada 1000 documentos)."""
    since = None
    if previous:
        since = datetime.fromisoformat(previous["generatedAt"].replace("Z", "+00:00")) - INCREMENTAL_MARGIN
    total = 0
    for collection in ("products", "storeProducts"):
        query = db.collection(collection)
        if since is not None:
            query = query.where(filter=FieldFilter("updatedAt", ">", since))
        total += int(query.count().get()[0][0].value) + 1
    return total + 30  # tiendas


def build_catalog(db, previous: dict | None, now: datetime | None = None) -> tuple[dict, dict]:
    """Devuelve `(catálogo, estadísticas)`. Con `previous`, solo lee lo que cambió."""
    now = now or datetime.now(timezone.utc)
    since = None
    products: dict[str, dict] = {}
    offers: dict[str, dict] = {}
    if previous:
        since = datetime.fromisoformat(previous["generatedAt"].replace("Z", "+00:00")) - INCREMENTAL_MARGIN
        products = {p["id"]: p for p in previous.get("products", [])}
        offers = {o["id"]: o for o in previous.get("offers", [])}

    reads = 0
    for snap in _changed(db, "products", since):
        reads += 1
        entry = product_entry(snap.id, snap.to_dict() or {})
        if entry:
            products[snap.id] = entry
        else:
            products.pop(snap.id, None)
    for snap in _changed(db, "storeProducts", since):
        reads += 1
        entry = offer_entry(snap.id, snap.to_dict() or {})
        if entry:
            offers[snap.id] = entry
        else:
            offers.pop(snap.id, None)
    stores = {}
    for snap in db.collection("stores").stream():
        reads += 1
        stores[snap.id] = store_entry(snap.id, snap.to_dict() or {})

    # Ofertas de productos que ya no se muestran (unificados o retirados) no sirven a la app.
    active_ids = {pid for pid, p in products.items() if p.get("status", "ACTIVE") == "ACTIVE"}
    offers = {oid: o for oid, o in offers.items() if o["productId"] in active_ids}

    categories = [_compact({k: c.get(k) for k in ("slug", "name", "parentSlug", "order", "icon")})
                  for c in flatten_categories() if c.get("status", "ACTIVE") == "ACTIVE"]
    catalog = {
        "version": FORMAT_VERSION,
        "generatedAt": _iso(now),
        "categories": categories,
        "stores": [stores[c] for c in sorted(stores)],
        "products": [products[p] for p in sorted(products)],
        "offers": [offers[o] for o in sorted(offers)],
    }
    stats = {"incremental": since is not None, "reads": max(reads, 1), "products": len(active_ids),
             "offers": len(offers)}
    return catalog, stats


def catalog_from_state(state: EngineState, stores: dict[str, dict], now: datetime | None = None) -> dict:
    """Catálogo armado desde la copia de trabajo del motor: 0 lecturas adicionales."""
    products = {pid: e for pid, d in state.products.items() if (e := product_entry(pid, d))}
    active_ids = {pid for pid, p in products.items() if p.get("status", "ACTIVE") == "ACTIVE"}
    offers = {oid: e for oid, d in state.listings.items()
              if (e := offer_entry(oid, d)) and e["productId"] in active_ids}
    categories = [_compact({k: c.get(k) for k in ("slug", "name", "parentSlug", "order", "icon")})
                  for c in flatten_categories() if c.get("status", "ACTIVE") == "ACTIVE"]
    return {
        "version": FORMAT_VERSION,
        "generatedAt": _iso(now or state.generated_at),
        "categories": categories,
        "stores": [store_entry(c, stores[c]) for c in sorted(stores)],
        "products": [products[p] for p in sorted(products)],
        "offers": [offers[o] for o in sorted(offers)],
    }


def estimate_full_state_reads(db, store_runs: dict, store_codes: list[str]) -> tuple[int, int]:
    """(lecturas estimadas, lecturas de los conteos) de una copia desde cero.

    Las publicaciones de las tiendas que corrieron vienen de sus archivos: solo cuentan los
    productos y las publicaciones de las tiendas que no corrieron.
    """
    total = int(db.collection("products").count().get()[0][0].value) + 1
    counts = 1
    for store in sorted(set(store_codes) - set(store_runs)):
        query = db.collection("storeProducts").where(filter=FieldFilter("storeCode", "==", store))
        total += int(query.count().get()[0][0].value) + 1
        counts += 1
    return total + 30, counts


def write_catalog(catalog: dict, out: Path) -> int:
    out.parent.mkdir(parents=True, exist_ok=True)
    data = json.dumps(catalog, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    out.write_bytes(data)
    return len(data)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    add_target_args(parser)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--previous-url", help="URL del catálogo publicado (exportación incremental).")
    parser.add_argument("--previous-file", type=Path, help="Catálogo previo local (pruebas).")
    parser.add_argument("--full", action="store_true", help="Ignorar el catálogo previo y leer todo.")
    parser.add_argument("--state", type=Path, help="Copia de trabajo del motor (se lee y se actualiza).")
    parser.add_argument("--store-states", type=Path, help="Carpeta con las publicaciones finales de cada tienda.")
    args = parser.parse_args(argv)
    db = resolve_db(args)
    if args.state:
        result = _export_with_state(db, args)
        if result is not None:
            return result
    published = load_previous(args.previous_url, args.previous_file)
    previous = None if args.full else published
    quota = QuotaTracker(db)
    estimate = estimate_reads(db, previous)
    if quota.used_reads + estimate > PROJECT_DAILY_READS_CAP:
        if previous is None and published is not None:
            previous = published  # sin cupo para rearmarlo completo: se actualiza solo lo cambiado
            estimate = estimate_reads(db, previous)
        if quota.used_reads + estimate > PROJECT_DAILY_READS_CAP:
            print(f"Sin cupo diario para exportar ({quota.used_reads} lecturas usadas hoy + ~{estimate}): "
                  "se mantiene el catálogo publicado y se reintenta en la próxima corrida.")
            if published is not None:
                write_catalog(published, args.out)  # se vuelve a publicar el mismo
            return 3 if published is None else 0
    catalog, stats = build_catalog(db, previous)
    quota.record(stats["reads"] + 2, 0)
    size = write_catalog(catalog, args.out)
    gz = len(gzip.compress(args.out.read_bytes()))
    print(f"Catálogo {'incremental' if stats['incremental'] else 'completo'}: {stats['products']} productos, "
          f"{stats['offers']} ofertas, {stats['reads']} lecturas de Firestore, "
          f"{size / 1024:.0f} KB ({gz / 1024:.0f} KB comprimido)")
    return 0



def _export_with_state(db, args) -> int | None:
    """Actualiza la copia de trabajo y arma el catálogo desde ella. None = usar la vía anterior."""
    quota = QuotaTracker(db)
    previous = None if args.full else EngineState.load(args.state)
    store_runs = load_store_listings(args.store_states)
    stores = {snap.id: snap.to_dict() or {} for snap in db.collection("stores").stream()}
    reads = len(stores) + 1
    if previous is None:
        estimate, counts = estimate_full_state_reads(db, store_runs, sorted(stores))
        reads += counts
        if quota.used_reads + estimate > PROJECT_DAILY_READS_CAP:
            print(f"Sin cupo para armar la copia de trabajo completa (~{estimate} lecturas; hoy van "
                  f"{quota.used_reads}): se intenta en la próxima corrida.")
            quota.record(reads, 0)
            return None
    state, state_reads = build_state(db, previous, store_runs, sorted(stores))
    reads += state_reads
    state.save(args.state)
    (args.state.parent / ".updated").touch()  # el workflow solo guarda la caché si cambió
    catalog = catalog_from_state(state, stores)
    size = write_catalog(catalog, args.out)
    quota.record(reads, 0)
    gz = len(gzip.compress(args.out.read_bytes()))
    print(f"Copia de trabajo {'completa' if previous is None else 'incremental'}: {len(state.products)} "
          f"productos, {len(state.listings)} publicaciones ({len(store_runs)} tiendas de esta corrida), "
          f"{reads} lecturas de Firestore.")
    print(f"Catálogo: {len(catalog['products'])} productos, {len(catalog['offers'])} ofertas, "
          f"{size / 1024:.0f} KB ({gz / 1024:.0f} KB comprimido)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
