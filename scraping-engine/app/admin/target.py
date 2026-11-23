"""Selección segura del destino (emulador o producción) para los scripts de administración."""

from __future__ import annotations

import argparse

from app.firebase_client import get_db, has_production_credentials, using_emulator


def add_target_args(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--prod", action="store_true", help="Escribir en el proyecto REAL (precio-justo-pe).")
    parser.add_argument("--yes", action="store_true", help="Confirmar la escritura en producción.")


def resolve_db(args: argparse.Namespace):
    """Devuelve el cliente de Firestore o lanza SystemExit con un mensaje claro."""
    if args.prod:
        if using_emulator():
            raise SystemExit("ERROR: --prod con FIRESTORE_EMULATOR_HOST definido. Quita la variable para usar producción.")
        if not has_production_credentials():
            raise SystemExit("ERROR: --prod requiere GOOGLE_APPLICATION_CREDENTIALS o FIREBASE_SERVICE_ACCOUNT.")
        if not args.yes:
            raise SystemExit("ERROR: escribir en PRODUCCIÓN requiere confirmar con --yes.")
        print(">> Destino: PRODUCCIÓN")
    else:
        if not using_emulator():
            raise SystemExit(
                "ERROR: define FIRESTORE_EMULATOR_HOST=127.0.0.1:8085 (emulador) o usa --prod --yes (producción)."
            )
        print(">> Destino: emulador")
    return get_db()
