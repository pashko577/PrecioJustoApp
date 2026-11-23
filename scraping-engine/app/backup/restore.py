"""Restaura un respaldo JSONL (de `app.backup.export`) en Firestore.

Por defecto restaura en el EMULADOR (para verificar que el respaldo sirve). Restaurar en
producción sobrescribe documentos: exige `--prod --yes`.

Uso:
    python -m app.backup.restore salida/compramejor-XXXX.jsonl.gz
    python -m app.backup.restore archivo.jsonl.gz --prod --yes
"""

from __future__ import annotations

import argparse
import gzip
import json
import sys
from pathlib import Path

from app.admin.target import add_target_args, resolve_db
from app.backup.export import decode_value


def restore(db, path: Path) -> int:
    count = 0
    batch, pending = db.batch(), 0
    with gzip.open(path, "rt", encoding="utf-8") as f:
        for line in f:
            if not line.strip():
                continue
            record = json.loads(line)
            batch.set(db.document(record["path"]), decode_value(record["data"], db))
            count += 1
            pending += 1
            if pending >= 400:
                batch.commit()
                batch, pending = db.batch(), 0
    if pending:
        batch.commit()
    return count


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("file", type=Path)
    add_target_args(parser)
    args = parser.parse_args(argv)
    count = restore(resolve_db(args), args.file)
    print(f"Documentos restaurados: {count}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
