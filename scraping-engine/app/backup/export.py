"""Respaldo de Firestore a archivos JSONL comprimidos (RNF-10).

Los respaldos administrados de Firestore requieren plan de pago; este script lo reemplaza.

- Catálogo (sin datos personales): categories, stores, config, products, storeProducts
  (+ su historial), scrapingJobs y auditLogs.
- Datos de usuarios (personales, Ley 29733): users y sus subcolecciones. Solo se incluyen con
  `--include-users`, y el workflow SOLO lo hace si el respaldo se cifra (BACKUP_PASSPHRASE).

Uso:
    python -m app.backup.export salida/                       # emulador, solo catálogo
    python -m app.backup.export salida/ --include-users       # emulador, todo
    python -m app.backup.export salida/ --prod --yes          # producción
"""

from __future__ import annotations

import argparse
import base64
import gzip
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

from google.cloud.firestore_v1 import GeoPoint
from google.cloud.firestore_v1.document import DocumentReference

from app.admin.target import add_target_args, resolve_db

CATALOG_COLLECTIONS = ["categories", "stores", "config", "products", "storeProducts", "scrapingJobs", "auditLogs"]
USER_COLLECTIONS = ["users"]


def encode_value(value):
    """Convierte tipos de Firestore a JSON conservando el tipo (para restaurar sin pérdidas)."""
    if isinstance(value, datetime):
        return {"__type": "timestamp", "value": value.astimezone(timezone.utc).isoformat()}
    if isinstance(value, GeoPoint):
        return {"__type": "geopoint", "lat": value.latitude, "lng": value.longitude}
    if isinstance(value, bytes):
        return {"__type": "bytes", "value": base64.b64encode(value).decode()}
    if isinstance(value, DocumentReference):
        return {"__type": "ref", "path": value.path}
    if isinstance(value, dict):
        return {k: encode_value(v) for k, v in value.items()}
    if isinstance(value, list):
        return [encode_value(v) for v in value]
    return value


def decode_value(value, db=None):
    if isinstance(value, dict):
        kind = value.get("__type")
        if kind == "timestamp":
            return datetime.fromisoformat(value["value"])
        if kind == "geopoint":
            return GeoPoint(value["lat"], value["lng"])
        if kind == "bytes":
            return base64.b64decode(value["value"])
        if kind == "ref":
            return db.document(value["path"]) if db is not None else value["path"]
        return {k: decode_value(v, db) for k, v in value.items()}
    if isinstance(value, list):
        return [decode_value(v, db) for v in value]
    return value


def _walk(collection, out, counter: dict):
    """Exporta una colección y, recursivamente, todas sus subcolecciones."""
    for snap in collection.stream():
        out.write(json.dumps({"path": snap.reference.path, "data": encode_value(snap.to_dict() or {})},
                             ensure_ascii=False) + "\n")
        counter[collection.id] = counter.get(collection.id, 0) + 1
        for sub in snap.reference.collections():
            _walk(sub, out, counter)


def export(db, folder: Path, include_users: bool) -> dict:
    folder.mkdir(parents=True, exist_ok=True)
    names = CATALOG_COLLECTIONS + (USER_COLLECTIONS if include_users else [])
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    path = folder / f"compramejor-{stamp}.jsonl.gz"
    counter: dict[str, int] = {}
    with gzip.open(path, "wt", encoding="utf-8") as out:
        for name in names:
            _walk(db.collection(name), out, counter)
    manifest = {
        "createdAt": stamp,
        "file": path.name,
        "includesPersonalData": include_users,
        "collections": names,
        "documents": counter,
        "total": sum(counter.values()),
    }
    (folder / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2), "utf-8")
    return manifest


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("folder", type=Path)
    parser.add_argument("--include-users", action="store_true", help="Incluir datos personales (cifrar el resultado).")
    add_target_args(parser)
    args = parser.parse_args(argv)
    manifest = export(resolve_db(args), args.folder, args.include_users)
    print(json.dumps(manifest, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
