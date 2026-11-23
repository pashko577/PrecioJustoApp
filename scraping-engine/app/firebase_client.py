"""Conexión a Firestore con el Admin SDK.

- Desarrollo: si existe FIRESTORE_EMULATOR_HOST, se conecta al emulador local (sin credenciales).
- Producción: credenciales de una cuenta de servicio, por una de estas vías:
    * FIREBASE_SERVICE_ACCOUNT = contenido JSON (GitHub Actions, como secret).
    * GOOGLE_APPLICATION_CREDENTIALS = ruta a un archivo JSON FUERA del repositorio (uso local).
  Nunca guardar ese JSON en el repositorio.
"""

from __future__ import annotations

import json
import os

import firebase_admin
from firebase_admin import credentials, firestore
from google.auth.credentials import AnonymousCredentials

DEMO_PROJECT_ID = "demo-precio-justo"
PROD_PROJECT_ID = "precio-justo-pe"


class _EmulatorCredential(credentials.Base):
    """Credencial anónima: los emuladores no validan credenciales."""

    def get_credential(self):
        return AnonymousCredentials()


def using_emulator() -> bool:
    return bool(os.getenv("FIRESTORE_EMULATOR_HOST"))


def has_production_credentials() -> bool:
    return bool(os.getenv("FIREBASE_SERVICE_ACCOUNT") or os.getenv("GOOGLE_APPLICATION_CREDENTIALS"))


def get_db():
    if not firebase_admin._apps:
        if using_emulator():
            project_id = os.getenv("GCLOUD_PROJECT", DEMO_PROJECT_ID)
            firebase_admin.initialize_app(_EmulatorCredential(), {"projectId": project_id})
        elif raw := os.getenv("FIREBASE_SERVICE_ACCOUNT"):
            firebase_admin.initialize_app(credentials.Certificate(json.loads(raw)))
        elif path := os.getenv("GOOGLE_APPLICATION_CREDENTIALS"):
            firebase_admin.initialize_app(credentials.Certificate(path))
        else:
            raise RuntimeError(
                "Sin destino de Firestore. Para desarrollo define FIRESTORE_EMULATOR_HOST=127.0.0.1:8085 "
                "y levanta los emuladores; para producción define FIREBASE_SERVICE_ACCOUNT o "
                "GOOGLE_APPLICATION_CREDENTIALS."
            )
    return firestore.client()
