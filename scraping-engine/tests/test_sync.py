"""La sincronización de configuración solo escribe lo que cambió (cuota de escrituras)."""

from datetime import datetime, timezone

from app.admin.sync import differs, write_changed


class FakeSnap:
    def __init__(self, doc_id, data):
        self.id, self._data = doc_id, data

    def to_dict(self):
        return dict(self._data)


class FakeDb:
    """Lo mínimo de Firestore que usa write_changed."""

    def __init__(self, data):
        self.data = {k: dict(v) for k, v in data.items()}
        self.writes = 0
        self.pending = []

    def collection(self, name):
        db = self

        class Col:
            def stream(self):
                return [FakeSnap(k, v) for k, v in db.data.items()]

            def document(self, doc_id):
                return doc_id

        return Col()

    def batch(self):
        db = self

        class Batch:
            def set(self, ref, data, merge=False):
                db.pending.append((ref, data))

            def commit(self):
                for ref, data in db.pending:
                    db.data.setdefault(ref, {}).update(data)
                    db.writes += 1
                db.pending.clear()

        return Batch()


def test_differs_ignores_volatile_and_extra_fields():
    stored = {"name": "Coolbox", "updatedAt": "ayer", "lastCompleteRunAt": datetime(2026, 1, 1, tzinfo=timezone.utc)}
    assert not differs(stored, {"name": "Coolbox", "updatedAt": "SERVER_TIMESTAMP"})
    assert differs(stored, {"name": "Coolbox Perú"})
    assert differs(None, {"name": "x"})


def test_only_new_or_changed_documents_are_written():
    db = FakeDb({"A": {"name": "A", "order": 1}, "B": {"name": "B", "order": 2}})
    written, unchanged = write_changed(db, "categories", {
        "A": {"name": "A", "order": 1},      # igual
        "B": {"name": "B", "order": 3},      # cambió
        "C": {"name": "C", "order": 4},      # nuevo
    })
    assert (written, unchanged) == (2, 1)
    assert db.writes == 2


def test_second_sync_writes_nothing():
    db = FakeDb({})
    docs = {"A": {"name": "A"}, "B": {"name": "B"}}
    assert write_changed(db, "stores", docs) == (2, 0)
    assert write_changed(db, "stores", docs) == (0, 2)
    assert db.writes == 2
