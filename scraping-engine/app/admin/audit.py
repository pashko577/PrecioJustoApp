"""Auditoría de acciones administrativas (`auditLogs`, RNF-07 y sección 13.1)."""

from __future__ import annotations

import getpass
import os
from datetime import datetime, timezone


def current_actor() -> str:
    """Quién ejecuta el script: usuario de GitHub Actions, variable explícita o usuario del sistema."""
    return os.getenv("ADMIN_ACTOR") or os.getenv("GITHUB_ACTOR") or f"local:{getpass.getuser()}"


def log_action(db, action: str, entity_type: str, entity_id: str, details: dict | None = None) -> None:
    db.collection("auditLogs").add({
        "actor": current_actor(),
        "actorUid": None,  # acciones hechas desde scripts (sin sesión de la app)
        "action": action,
        "entityType": entity_type,
        "entityId": entity_id,
        "details": details or {},
        "createdAt": datetime.now(timezone.utc),
    })
