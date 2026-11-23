"""Carga o actualiza el árbol de categorías (`app/data/categories.json`).

Uso:
    python -m app.admin.categories                 # emulador
    python -m app.admin.categories --prod --yes    # proyecto real
"""

from __future__ import annotations

import argparse
import sys

from app.admin.target import add_target_args, resolve_db
from app.catalog import flatten_categories


def upload_categories(db, categories: list[dict]) -> int:
    batch = db.batch()
    for c in categories:
        batch.set(db.collection("categories").document(c["slug"]), c, merge=True)
    batch.commit()
    return len(categories)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    add_target_args(parser)
    args = parser.parse_args(argv)
    categories = flatten_categories()
    db = resolve_db(args)
    count = upload_categories(db, categories)
    print(f"Categorías cargadas: {count}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
