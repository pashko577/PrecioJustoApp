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
    allowed = allowed_image_stores(store_info(db))
    query = db.collection("products").where(filter=FieldFilter("imageUrl", ">", ""))
    batch, pending, cleared = db.batch(), 0, 0
    for snap in query.stream():
        if (snap.to_dict() or {}).get("imageStoreCode") in allowed:
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
