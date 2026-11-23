"""Presupuesto diario de Firestore para el motor (plan Spark, sin costo).

El plan gratuito permite por día 50 000 lecturas, 20 000 escrituras y 20 000 borrados; al
pasarse, Firestore responde "429 Quota exceeded" hasta la medianoche del Pacífico (03:00 en
Lima) y la app también deja de funcionar. El motor se reserva una parte y deja el resto para
los usuarios de la app.

El consumo del día se acumula en `system/quota-AAAA-MM-DD` (fecha del Pacífico, que es cuando
Google reinicia la cuota). Cada corrida lee ese documento (1 lectura), recibe un tope y, al
terminar, suma lo que gastó (1 escritura). Las cifras son estimaciones conservadoras.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timedelta, timezone

from firebase_admin import firestore

# Parte de la cuota diaria que puede usar el motor (el resto queda para la app).
ENGINE_DAILY_READS = 38_000
ENGINE_DAILY_WRITES = 15_000
# Tope por corrida de una tienda: una sola tienda no puede gastarse el día entero.
RUN_MAX_READS = 9_000
RUN_MAX_WRITES = 3_500
# Margen para lo que se hace al cerrar (resúmenes, alertas, job): no se corta a mitad.
CLOSE_RESERVE_WRITES = 300


def quota_day(now: datetime | None = None) -> str:
    """Día de cuota de Firestore: medianoche del Pacífico (UTC-8; en horario de verano UTC-7)."""
    now = now or datetime.now(timezone.utc)
    try:
        from zoneinfo import ZoneInfo

        local = now.astimezone(ZoneInfo("America/Los_Angeles"))
    except Exception:  # sin base de zonas horarias: UTC-8 es el caso conservador
        local = now.astimezone(timezone(timedelta(hours=-8)))
    return local.strftime("%Y-%m-%d")


@dataclass
class RunBudget:
    reads: int
    writes: int

    @property
    def exhausted(self) -> bool:
        return self.reads <= 0 or self.writes <= CLOSE_RESERVE_WRITES


def run_budget(used_reads: int, used_writes: int) -> RunBudget:
    """Tope de esta corrida según lo que ya se gastó hoy."""
    return RunBudget(
        reads=max(0, min(RUN_MAX_READS, ENGINE_DAILY_READS - used_reads)),
        writes=max(0, min(RUN_MAX_WRITES, ENGINE_DAILY_WRITES - used_writes)),
    )


class QuotaTracker:
    """Lee el consumo del día al abrir y lo suma al cerrar."""

    def __init__(self, db, now: datetime | None = None):
        self.db = db
        self.ref = db.collection("system").document(f"quota-{quota_day(now)}")
        snap = self.ref.get()
        data = snap.to_dict() if snap.exists else {}
        self.used_reads = int((data or {}).get("reads", 0))
        self.used_writes = int((data or {}).get("writes", 0))
        self.budget = run_budget(self.used_reads, self.used_writes)

    def record(self, reads: int, writes: int, deletes: int = 0) -> None:
        self.ref.set({
            "reads": firestore.Increment(reads + 1),      # + la lectura de este documento
            "writes": firestore.Increment(writes + 1),    # + esta escritura
            "deletes": firestore.Increment(deletes),
            "updatedAt": firestore.SERVER_TIMESTAMP,
        }, merge=True)
