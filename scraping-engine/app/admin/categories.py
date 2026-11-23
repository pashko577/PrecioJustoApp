"""Carga o actualiza el árbol de categorías (`app/data/categories.json`).

Uso:
    python -m app.admin.categories                 # emulador
    python -m app.admin.categories --prod --yes    # proyecto real
"""

from __future__ import annotations

import argparse
import sys

from app.admin.sync import write_changed
from app.admin.target import add_target_args, resolve_db
from app.catalog import flatten_categories


def upload_categories(db, categories: list[dict]) -> tuple[int, int]:
    """Carga las categorías; solo escribe las nuevas o cambiadas. Devuelve (escritas, sin cambios)."""
    return write_changed(db, "categories", {c["slug"]: c for c in categories})


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    add_target_args(parser)
    args = parser.parse_args(argv)
    categories = flatten_categories()
    db = resolve_db(args)
    written, unchanged = upload_categories(db, categories)
    print(f"Categorías: {written} actualizadas, {unchanged} sin cambios")
    return 0


if __name__ == "__main__":
    sys.exit(main())
