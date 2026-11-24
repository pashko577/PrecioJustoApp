"""Quita de los productos las fotos de tiendas que no dieron permiso (`showImages`).

Las fotos de producto son de las tiendas o de las marcas (derecho de autor, D. Leg. 822): solo se
muestran las de tiendas con permiso o licencia (por ejemplo, un programa de afiliados). Es
idempotente: lo corre el workflow en cada ejecución y, sin fotos pendientes, cuesta 1 lectura.

Uso:
    python -m app.admin.images                 # emulador
    python -m app.admin.images --prod --yes    # proyecto real
"""

from __future__ import annotations

import argparse
import sys

from firebase_admin import firestore
from google.cloud.firestore_v1.base_query import FieldFilter

from app.admin.target import add_target_args, resolve_db
from app.postprocess.summary import allowed_image_stores, store_info


def clear_disallowed_images(db) -> int:
    """Borra `imageUrl` de los productos cuya foto no viene de una tienda permitida."""
    stores = store_info(db)
    allowed = allowed_image_stores(stores)
    active = {code for code, s in stores.items() if s.get("scrapingEnabled")}
    # Fotos guardadas antes de registrar su tienda (sin `imageStoreCode`): se conservan solo si
    # todas las tiendas activas permiten fotos (pudo venir de cualquiera de ellas).
    keep_unknown = bool(active) and active <= allowed
    if keep_unknown:
        # Caso normal: solo se buscan fotos de tiendas sin permiso (casi siempre 0 → 1 lectura),
        # en vez de recorrer todos los productos con foto en cada corrida.
        disallowed = sorted(set(stores) - allowed)[:30]  # `in` admite hasta 30 valores
        if not disallowed:
            return 0
        query = db.collection("products").where(filter=FieldFilter("imageStoreCode", "in", disallowed))
    else:
        query = db.collection("products").where(filter=FieldFilter("imageUrl", ">", ""))
    batch, pending, cleared = db.batch(), 0, 0
    for snap in query.stream():
        store = (snap.to_dict() or {}).get("imageStoreCode")
        if store in allowed or (store is None and keep_unknown):
            continue
        batch.update(snap.reference, {"imageUrl": firestore.DELETE_FIELD,
                                      "imageStoreCode": firestore.DELETE_FIELD})
        pending += 1
        cleared += 1
        if pending >= 400:
            batch.commit()
            batch, pending = db.batch(), 0
    if pending:
        batch.commit()
    return cleared


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    add_target_args(parser)
    args = parser.parse_args(argv)
    cleared = clear_disallowed_images(resolve_db(args))
    print(f"Fotos retiradas (tiendas sin permiso): {cleared}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
