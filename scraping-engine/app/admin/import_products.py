"""Carga inicial de productos del catálogo normalizado desde un archivo JSON.

Formato: lista de objetos con los campos de `app.catalog.ProductInput`, por ejemplo:
    [{"category": "ssd", "brand": "Kingston", "model": "NV3", "name": "Kingston NV3 1TB",
      "attributes": {"capacidad": "1 TB"}, "identifiers": {"EAN": ["2001234567893"]}}]

Uso:
    python -m app.admin.import_products app/data/sample_products.json            # emulador
    python -m app.admin.import_products archivo.json --dry-run                    # solo valida
    python -m app.admin.import_products archivo.json --prod --yes                 # proyecto real

Los productos existentes se actualizan (sin tocar su resumen de precios ni su fecha de creación).
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from firebase_admin import firestore

from app.admin.target import add_target_args, resolve_db
from app.catalog import CatalogError, ProductInput, build_product_doc, empty_summary, flatten_categories


def load_products(path: Path, valid_categories: set[str]) -> list[tuple[str, dict]]:
    """Valida todo el archivo antes de escribir. Lanza CatalogError con todos los errores."""
    raw = json.loads(path.read_text("utf-8"))
    if not isinstance(raw, list):
        raise CatalogError("El archivo debe contener una lista de productos.")
    docs, errors, seen = [], [], set()
    for index, record in enumerate(raw, start=1):
        try:
            product_id, data = build_product_doc(ProductInput(**record), valid_categories)
        except TypeError as exc:
            errors.append(f"#{index}: campos inválidos ({exc})")
            continue
        except CatalogError as exc:
            errors.append(f"#{index}: {exc}")
            continue
        if product_id in seen:
            errors.append(f"#{index}: id duplicado {product_id!r}")
            continue
        seen.add(product_id)
        docs.append((product_id, data))
    if errors:
        raise CatalogError("Errores en el archivo:\n  " + "\n  ".join(errors))
    return docs


def write_products(db, docs: list[tuple[str, dict]]) -> tuple[int, int]:
    """Escribe en lotes de hasta 400. Devuelve (creados, actualizados)."""
    created = updated = 0
    collection = db.collection("products")
    for start in range(0, len(docs), 400):
        chunk = docs[start:start + 400]
        refs = [collection.document(pid) for pid, _ in chunk]
        existing = {snap.id for snap in db.get_all(refs) if snap.exists}
        batch = db.batch()
        for (pid, data), ref in zip(chunk, refs):
            data = {**data, "updatedAt": firestore.SERVER_TIMESTAMP}
            if pid in existing:
                updated += 1
            else:
                created += 1
                data.update({"summary": empty_summary(), "createdAt": firestore.SERVER_TIMESTAMP})
            batch.set(ref, data, merge=True)
        batch.commit()
    return created, updated


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("file", type=Path)
    parser.add_argument("--dry-run", action="store_true", help="Solo valida el archivo, no escribe.")
    add_target_args(parser)
    args = parser.parse_args(argv)

    valid_categories = {c["slug"] for c in flatten_categories()}
    try:
        docs = load_products(args.file, valid_categories)
    except CatalogError as exc:
        print(exc)
        return 1
    print(f"Archivo válido: {len(docs)} productos.")
    if args.dry_run:
        return 0

    created, updated = write_products(resolve_db(args), docs)
    print(f"Productos creados: {created} · actualizados: {updated}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
