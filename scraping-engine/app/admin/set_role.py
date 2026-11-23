"""Asigna o quita roles (custom claims de Firebase Auth): `admin` u `operator`.

Uso:
    python -m app.admin.set_role correo@ejemplo.com admin               # emulador
    python -m app.admin.set_role correo@ejemplo.com admin --remove
    python -m app.admin.set_role correo@ejemplo.com admin --prod --yes  # proyecto real

En el emulador también se necesita FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9099.
El usuario debe cerrar e iniciar sesión (o esperar ~1 h) para que su sesión tome el rol nuevo.
"""

from __future__ import annotations

import argparse
import os
import sys

from firebase_admin import auth

from app.admin.audit import log_action
from app.admin.target import add_target_args, resolve_db

ROLES = ("admin", "operator")


def set_role(db, email: str, role: str, remove: bool = False) -> dict:
    if role not in ROLES:
        raise ValueError(f"Rol desconocido: {role}. Válidos: {', '.join(ROLES)}")
    user = auth.get_user_by_email(email.strip().lower())
    claims = dict(user.custom_claims or {})
    if remove:
        claims.pop(role, None)
    else:
        claims[role] = True
    auth.set_custom_user_claims(user.uid, claims or None)
    log_action(db, "ROLE_REMOVED" if remove else "ROLE_GRANTED", "user", user.uid, {"role": role})
    return claims


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("email")
    parser.add_argument("role", choices=ROLES)
    parser.add_argument("--remove", action="store_true", help="Quitar el rol en vez de asignarlo.")
    add_target_args(parser)
    args = parser.parse_args(argv)
    if not args.prod and not os.getenv("FIREBASE_AUTH_EMULATOR_HOST"):
        print("ERROR: define FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9099 (emulador) o usa --prod --yes.")
        return 1
    db = resolve_db(args)
    try:
        claims = set_role(db, args.email, args.role, args.remove)
    except auth.UserNotFoundError:
        print(f"ERROR: no existe un usuario con el correo {args.email}.")
        return 1
    print(f"Roles de {args.email}: {sorted(claims) or 'ninguno'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
