"""Pruebas de integración contra los emuladores de Firebase.

Se ejecutan con:
    firebase emulators:exec --only firestore,auth --project demo-precio-justo \
        "cd scraping-engine && python -m pytest -q tests_emulator"
Sin emuladores (FIRESTORE_EMULATOR_HOST no definido) se omiten.
"""

import os
import urllib.request

import pytest

PROJECT = "demo-precio-justo"


def pytest_collection_modifyitems(config, items):
    if os.getenv("FIRESTORE_EMULATOR_HOST"):
        return
    skip = pytest.mark.skip(reason="requiere los emuladores de Firebase")
    for item in items:
        if "tests_emulator" in str(item.fspath):
            item.add_marker(skip)


def _delete(url: str) -> None:
    req = urllib.request.Request(url, method="DELETE")
    urllib.request.urlopen(req, timeout=10).read()


@pytest.fixture
def db():
    """Firestore del emulador, vacío al inicio de cada prueba."""
    os.environ.setdefault("GCLOUD_PROJECT", PROJECT)
    host = os.environ["FIRESTORE_EMULATOR_HOST"]
    _delete(f"http://{host}/emulator/v1/projects/{PROJECT}/databases/(default)/documents")
    from app.firebase_client import get_db
    return get_db()


@pytest.fixture
def auth_emulator(db):
    """Auth del emulador, vacío al inicio de cada prueba."""
    host = os.getenv("FIREBASE_AUTH_EMULATOR_HOST")
    if not host:
        pytest.skip("requiere el emulador de Auth")
    _delete(f"http://{host}/emulator/v1/projects/{PROJECT}/accounts")
    from firebase_admin import auth
    return auth
