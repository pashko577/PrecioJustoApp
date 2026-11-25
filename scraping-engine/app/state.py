"""Copia de trabajo del motor: productos y publicaciones, para no releerlos de Firestore.

El plan gratuito da 50 000 lecturas al día. Antes, cada tienda leía al empezar todas sus
publicaciones y todos los productos de sus categorías (unas 30 000 lecturas diarias en total).
Ahora:

1. Al terminar cada corrida, el job «Publicar catálogo» arma esta copia (`engine-state.json.gz`)
   y la guarda en la caché de GitHub Actions (privada y gratuita).
2. Cada tienda, al empezar, carga la copia y solo pregunta a Firestore lo que cambió desde
   entonces (`updatedAt`), por ejemplo una aprobación manual.
3. Al terminar, cada tienda deja sus publicaciones finales (`state-out/{TIENDA}.json.gz`): el job
   final las usa tal cual, así también sabe cuáles se borraron.

Firestore sigue siendo la fuente oficial: si la copia falta, está dañada o es muy vieja, el motor
lee Firestore como antes.
"""

from __future__ import annotations

import gzip
import json
import os
from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone
from pathlib import Path

from google.cloud.firestore_v1.base_query import FieldFilter

STATE_VERSION = 1
# Margen ante relojes desfasados y escrituras en curso cuando se armó la copia.
STATE_MARGIN = timedelta(minutes=30)
# Una copia más vieja que esto no se usa (se vuelve a leer Firestore).
MAX_STATE_AGE = timedelta(days=3)
# Campos grandes que el motor no necesita leer (se recalculan al escribir).
_DROP_PRODUCT_FIELDS = ("searchTokens",)
_DROP_LISTING_FIELDS = ("titleTokens",)


def _encode(value):
    if isinstance(value, datetime):
        if value.tzinfo is None:
            value = value.replace(tzinfo=timezone.utc)
        return {"$t": value.astimezone(timezone.utc).isoformat()}
    if isinstance(value, dict):
        return {k: _encode(v) for k, v in value.items()}
    if isinstance(value, (list, tuple)):
        return [_encode(v) for v in value]
    return value


def _decode(value):
    if isinstance(value, dict):
        if set(value) == {"$t"}:
            return datetime.fromisoformat(value["$t"])
        return {k: _decode(v) for k, v in value.items()}
    if isinstance(value, list):
        return [_decode(v) for v in value]
    return value


def product_doc(data: dict) -> dict:
    return {k: v for k, v in data.items() if k not in _DROP_PRODUCT_FIELDS}


def listing_doc(data: dict) -> dict:
    return {k: v for k, v in data.items() if k not in _DROP_LISTING_FIELDS}


def _write_gz(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_bytes(gzip.compress(json.dumps(_encode(payload), ensure_ascii=False,
                                             separators=(",", ":")).encode("utf-8")))
    tmp.replace(path)


def _read_gz(path: Path) -> dict | None:
    try:
        return _decode(json.loads(gzip.decompress(path.read_bytes())))
    except (OSError, ValueError, EOFError):
        return None


@dataclass
class EngineState:
    generated_at: datetime
    products: dict[str, dict] = field(default_factory=dict)
    listings: dict[str, dict] = field(default_factory=dict)

    @classmethod
    def load(cls, path: str | Path | None, now: datetime | None = None) -> EngineState | None:
        """Copia guardada, o None si no hay, está dañada, es de otro formato o es muy vieja."""
        if not path or not Path(path).exists():
            return None
        data = _read_gz(Path(path))
        if not data or data.get("version") != STATE_VERSION:
            return None
        state = cls(data["generatedAt"], data.get("products", {}), data.get("listings", {}))
        if (now or datetime.now(timezone.utc)) - state.generated_at > MAX_STATE_AGE:
            return None
        return state

    def save(self, path: str | Path) -> None:
        _write_gz(Path(path), {"version": STATE_VERSION, "generatedAt": self.generated_at,
                               "products": self.products, "listings": self.listings})

    @property
    def since(self) -> datetime:
        return self.generated_at - STATE_MARGIN

    def store_listings(self, store_code: str) -> dict[str, dict]:
        return {k: v for k, v in self.listings.items() if v.get("storeCode") == store_code}


# ---- Publicaciones finales de una tienda (las deja cada job de extracción) ----

def save_store_listings(directory: str | Path, store_code: str, listings: dict[str, dict]) -> Path:
    path = Path(directory) / f"{store_code}.json.gz"
    _write_gz(path, {"version": STATE_VERSION, "storeCode": store_code,
                     "listings": {k: listing_doc(v) for k, v in listings.items()}})
    return path


def load_store_listings(directory: str | Path | None) -> dict[str, dict[str, dict]]:
    """`{TIENDA: {id: publicación}}` de los jobs de esta corrida (ignora archivos dañados)."""
    result: dict[str, dict[str, dict]] = {}
    if not directory or not Path(directory).is_dir():
        return result
    for path in sorted(Path(directory).rglob("*.json.gz")):
        data = _read_gz(path)
        if data and data.get("version") == STATE_VERSION and data.get("storeCode"):
            result[data["storeCode"]] = data.get("listings", {})
    return result


def state_path_from_env() -> str | None:
    return os.getenv("ENGINE_STATE") or None


def store_out_dir_from_env() -> str | None:
    return os.getenv("ENGINE_STATE_OUT") or None


# ---- Lecturas a Firestore ----

def changed_products(db, since: datetime | None):
    query = db.collection("products")
    if since is not None:
        query = query.where(filter=FieldFilter("updatedAt", ">", since))
    return query.stream()


def changed_store_listings(db, store_code: str, since: datetime | None):
    """Publicaciones de una tienda (cambiadas desde `since`). Usa el índice storeCode+updatedAt."""
    query = db.collection("storeProducts").where(filter=FieldFilter("storeCode", "==", store_code))
    if since is not None:
        query = query.where(filter=FieldFilter("updatedAt", ">", since))
    return query.stream()


def build_state(db, previous: EngineState | None, store_runs: dict[str, dict[str, dict]],
                store_codes: list[str], now: datetime | None = None) -> tuple[EngineState, int]:
    """Copia nueva. Con `previous`, solo lee de Firestore lo que cambió. Devuelve (copia, lecturas).

    - Productos: todos (copia desde cero) o los cambiados desde la copia anterior.
    - Publicaciones de tiendas que corrieron: las que dejó su job (exactas, incluye borrados).
    - Publicaciones de las demás tiendas: la copia anterior más lo cambiado (decisiones manuales).
    """
    now = now or datetime.now(timezone.utc)
    reads = 0
    since = previous.since if previous else None
    products = dict(previous.products) if previous else {}
    for snap in changed_products(db, since):
        reads += 1
        products[snap.id] = product_doc(snap.to_dict() or {})

    listings: dict[str, dict] = {}
    if previous is None:
        # Copia desde cero: las tiendas de esta corrida ya dejaron sus publicaciones completas;
        # solo se leen de Firestore las de las tiendas que no corrieron.
        for store, run in store_runs.items():
            listings.update(run)
        for store in sorted(set(store_codes) - set(store_runs)):
            found = 0
            for snap in changed_store_listings(db, store, None):
                found += 1
                listings[snap.id] = listing_doc(snap.to_dict() or {})
            reads += max(found, 1)
    else:
        for store in sorted(set(store_codes) | {v.get("storeCode") for v in previous.listings.values()}):
            if store in store_runs:
                listings.update(store_runs[store])
                continue
            current = previous.store_listings(store)
            found = 0
            for snap in changed_store_listings(db, store, since):
                found += 1
                current[snap.id] = listing_doc(snap.to_dict() or {})
            reads += max(found, 1)
            listings.update(current)
    return EngineState(now, products, listings), max(reads, 1)
