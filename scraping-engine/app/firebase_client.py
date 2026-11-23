"""Conexión a Firestore con el Admin SDK.

- Desarrollo: si existe FIRESTORE_EMULATOR_HOST, se conecta al emulador local (sin credenciales).
- Producción (GitHub Actions): FIREBASE_SERVICE_ACCOUNT contiene el JSON de la cuenta de servicio.
  Nunca guardar ese JSON en el repositorio.
"""

from __future__ import annotations

import json
import os

import firebase_admin
from firebase_admin import credentials, firestore
from google.auth.credentials import AnonymousCredentials

DEMO_PROJECT_ID = "demo-precio-justo"


class _EmulatorCredential(credentials.Base):
    """Credencial anónima: los emuladores no validan credenciales."""

    def get_credential(self):
        return AnonymousCredentials()


def using_emulator() -> bool:
    return bool(os.getenv("FIRESTORE_EMULATOR_HOST"))


def get_db():
    if not firebase_admin._apps:
        if using_emulator():
            project_id = os.getenv("GCLOUD_PROJECT", DEMO_PROJECT_ID)
            firebase_admin.initialize_app(_EmulatorCredential(), {"projectId": project_id})
        else:
            raw = os.getenv("FIREBASE_SERVICE_ACCOUNT")
            if not raw:
                raise RuntimeError(
                    "Falta FIREBASE_SERVICE_ACCOUNT. Para desarrollo local define "
                    "FIRESTORE_EMULATOR_HOST=127.0.0.1:8085 y levanta los emuladores."
                )
            firebase_admin.initialize_app(credentials.Certificate(json.loads(raw)))
    return firestore.client()
