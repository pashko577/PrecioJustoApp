"""Escritura de documentos de configuración solo si cambiaron (cuida la cuota de escrituras).

Leer la colección entera cuesta pocas lecturas (decenas de documentos) y la cuota de lecturas
es mayor; reescribirla en cada corrida gastaba cientos de escrituras al día sin cambiar nada.
"""

from __future__ import annotations

# Campos que cambian en cada envío y no cuentan como cambio real.
VOLATILE_FIELDS = frozenset({"updatedAt"})


def differs(current: dict | None, desired: dict) -> bool:
    """¿El documento guardado difiere en algún campo que queremos escribir?"""
    if current is None:
        return True
    return any(current.get(k) != v for k, v in desired.items() if k not in VOLATILE_FIELDS)


def write_changed(db, collection: str, docs: dict[str, dict]) -> tuple[int, int]:
    """Escribe (con merge) solo los documentos nuevos o distintos. Devuelve (escritos, sin cambios)."""
    existing = {snap.id: snap.to_dict() or {} for snap in db.collection(collection).stream()}
    changed = [doc_id for doc_id, data in docs.items() if differs(existing.get(doc_id), data)]
    if changed:
        batch = db.batch()
        for doc_id in changed:
            batch.set(db.collection(collection).document(doc_id), docs[doc_id], merge=True)
        batch.commit()
    return len(changed), len(docs) - len(changed)
