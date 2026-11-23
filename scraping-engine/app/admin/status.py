"""Estado del sistema: tiendas, frescura de datos, revisiones pendientes y últimos errores (RNF-11).

Uso:
    python -m app.admin.status                 # texto (emulador)
    python -m app.admin.status --markdown      # tabla Markdown (resumen de GitHub Actions)
    python -m app.admin.status --prod --yes
Sale con código 2 si alguna tienda activa está desactualizada (sirve para alertar en CI).
"""

from __future__ import annotations

import argparse
import sys
from datetime import datetime, timedelta, timezone

from google.cloud.firestore_v1.base_query import FieldFilter

from app.admin.target import add_target_args, resolve_db

OK, STALE, NEVER, DISABLED = "OK", "DESACTUALIZADA", "NUNCA CORRIÓ", "INACTIVA"


def store_health(store: dict, now: datetime) -> str:
    """Una tienda activa está desactualizada si su última corrida completa supera 2 intervalos + 1 h."""
    if not store.get("scrapingEnabled"):
        return DISABLED
    last = store.get("lastCompleteRunAt")
    if last is None:
        return NEVER
    interval = timedelta(minutes=int(store.get("scrapingIntervalMinutes") or 360))
    return OK if now - last <= 2 * interval + timedelta(hours=1) else STALE


def _count(query) -> int:
    result = query.count().get()
    return int(result[0][0].value)


def collect(db, now: datetime | None = None) -> dict:
    now = now or datetime.now(timezone.utc)
    stores = []
    for snap in db.collection("stores").stream():
        s = snap.to_dict() or {}
        base = db.collection("storeProducts").where(filter=FieldFilter("storeCode", "==", snap.id))
        stores.append({
            "code": snap.id,
            "name": s.get("name", snap.id),
            "health": store_health(s, now),
            "lastRunAt": s.get("lastRunAt"),
            "lastRunStatus": s.get("lastRunStatus"),
            "lastCompleteRunAt": s.get("lastCompleteRunAt"),
            "listings": _count(base.where(filter=FieldFilter("status", "==", "ACTIVE"))),
        })
    pending = _count(db.collection("storeProducts").where(filter=FieldFilter("matchStatus", "==", "PENDING_REVIEW")))
    unmatched = _count(db.collection("storeProducts").where(filter=FieldFilter("matchStatus", "==", "UNMATCHED")))
    products = _count(db.collection("products").where(filter=FieldFilter("status", "==", "ACTIVE")))
    return {"now": now, "stores": sorted(stores, key=lambda s: s["code"]), "pendingReview": pending,
            "unmatched": unmatched, "products": products}


def _ago(value: datetime | None, now: datetime) -> str:
    if value is None:
        return "—"
    hours = (now - value).total_seconds() / 3600
    return f"hace {hours:.0f} h" if hours >= 1 else f"hace {hours * 60:.0f} min"


def render(report: dict, markdown: bool) -> str:
    now = report["now"]
    if markdown:
        lines = ["## Estado de CompraMejor", "",
                 "| Tienda | Estado | Última corrida completa | Último resultado | Publicaciones activas |",
                 "|---|---|---|---|---|"]
        icon = {OK: "✅", STALE: "⚠️", NEVER: "⏳", DISABLED: "⏸️"}
        for s in report["stores"]:
            lines.append(f"| {s['name']} | {icon[s['health']]} {s['health']} | {_ago(s['lastCompleteRunAt'], now)} | "
                         f"{s['lastRunStatus'] or '—'} | {s['listings']:,} |")
        lines += ["", f"- Productos activos: **{report['products']:,}**",
                  f"- Asociaciones pendientes de revisión: **{report['pendingReview']}**",
                  f"- Publicaciones sin asociar: **{report['unmatched']}**"]
        return "\n".join(lines)
    lines = []
    for s in report["stores"]:
        lines.append(f"{s['name']:<12} {s['health']:<15} completa {_ago(s['lastCompleteRunAt'], now):<12} "
                     f"último {s['lastRunStatus'] or '—':<8} activas {s['listings']:,}")
    lines += [f"Productos activos: {report['products']:,}", f"Pendientes de revisión: {report['pendingReview']}",
              f"Sin asociar: {report['unmatched']}"]
    return "\n".join(lines)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--markdown", action="store_true")
    add_target_args(parser)
    args = parser.parse_args(argv)
    report = collect(resolve_db(args))
    print(render(report, args.markdown))
    return 2 if any(s["health"] == STALE for s in report["stores"]) else 0


if __name__ == "__main__":
    sys.exit(main())
