"""Revisión manual de asociaciones publicación -> producto (sección 8.2, nivel 4; RF-10).

Uso (emulador por defecto; producción con --prod --yes):
    python -m app.admin.review_matches list                          # pendientes de revisión
    python -m app.admin.review_matches list --status UNMATCHED       # sin asociar
    python -m app.admin.review_matches approve COOLBOX__123          # acepta la sugerencia
    python -m app.admin.review_matches assign COOLBOX__123 producto-x  # asocia a otro producto
    python -m app.admin.review_matches reject COOLBOX__123           # no corresponde a ninguno
    python -m app.admin.review_matches create COOLBOX__123           # crea un producto nuevo

Las decisiones manuales (MATCHED_MANUAL, REJECTED) se respetan en las corridas siguientes.
Cada acción recalcula los precios de los productos afectados y queda en auditLogs.
"""

from __future__ import annotations

import argparse
import sys

from firebase_admin import firestore
from google.cloud.firestore_v1.base_query import FieldFilter

from app.admin.audit import log_action
from app.admin.target import add_target_args, resolve_db
from app.catalog import CatalogError, ProductInput, build_product_doc, empty_summary, flatten_categories, slugify
from app.postprocess.summary import refresh_summaries


class ReviewError(ValueError):
    """Acción de revisión inválida (mensaje para el operador)."""


def list_listings(db, status: str = "PENDING_REVIEW", limit: int = 50) -> list[dict]:
    query = (db.collection("storeProducts").where(filter=FieldFilter("matchStatus", "==", status))
             .order_by("createdAt", direction=firestore.Query.DESCENDING).limit(limit))
    return [{"id": s.id, **(s.to_dict() or {})} for s in query.stream()]


def _listing(db, listing_id: str):
    ref = db.collection("storeProducts").document(listing_id)
    snap = ref.get()
    if not snap.exists:
        raise ReviewError(f"No existe la publicación {listing_id}")
    return ref, snap.to_dict() or {}


def _decide(db, listing_id: str, *, status: str, product_id: str | None, reason: str, action: str) -> None:
    ref, data = _listing(db, listing_id)
    previous = data.get("productId")
    ref.update({
        "productId": product_id,
        "matchStatus": status,
        "matchScore": 100 if status == "MATCHED_MANUAL" else data.get("matchScore"),
        "matchReason": reason,
        "updatedAt": firestore.SERVER_TIMESTAMP,
    })
    refresh_summaries(db, {p for p in (previous, product_id) if p})
    log_action(db, action, "storeProduct", listing_id,
               {"previousProductId": previous, "productId": product_id, "title": data.get("title")})


def approve(db, listing_id: str) -> str:
    _, data = _listing(db, listing_id)
    suggested = data.get("productId")
    if not suggested:
        raise ReviewError("La publicación no tiene un producto sugerido: usa 'assign' o 'create'.")
    _decide(db, listing_id, status="MATCHED_MANUAL", product_id=suggested,
            reason="aprobado manualmente", action="MATCH_APPROVED")
    return suggested


def assign(db, listing_id: str, product_id: str) -> None:
    if not db.collection("products").document(product_id).get().exists:
        raise ReviewError(f"No existe el producto {product_id}")
    _decide(db, listing_id, status="MATCHED_MANUAL", product_id=product_id,
            reason="asignado manualmente", action="MATCH_ASSIGNED")


def reject(db, listing_id: str) -> None:
    _decide(db, listing_id, status="REJECTED", product_id=None,
            reason="rechazado manualmente", action="MATCH_REJECTED")


def create(db, listing_id: str) -> str:
    _, data = _listing(db, listing_id)
    category = data.get("categoryHint")
    if not category:
        raise ReviewError("La publicación no tiene categoría: asígnala a un producto existente con 'assign'.")
    identifiers = {}
    ids = data.get("identifiers") or {}
    if ids.get("GTIN"):
        identifiers["GTIN"] = [ids["GTIN"]]
    if ids.get("MPN"):
        identifiers["MPN"] = [ids["MPN"]]
    base = slugify(f"{data.get('brand') or ''} {data.get('title')}")[:80].strip("-")
    product_id = base
    if db.collection("products").document(product_id).get().exists:
        product_id = f"{base[:70]}-{slugify(data.get('externalProductId') or listing_id)}"[:100]
    try:
        _, doc = build_product_doc(ProductInput(
            id=product_id, category=category, brand=data.get("brand") or "Genérico",
            model=data.get("model") or "N/D", name=data.get("title") or listing_id,
            condition=data.get("condition") or "NEW", identifiers=identifiers,
        ), {c["slug"] for c in flatten_categories()})
    except CatalogError as exc:
        raise ReviewError(str(exc)) from exc
    doc.update({
        "summary": empty_summary(),
        "source": {"storeCode": data.get("storeCode"), "externalProductId": data.get("externalProductId")},
        "createdAt": firestore.SERVER_TIMESTAMP,
        "updatedAt": firestore.SERVER_TIMESTAMP,
    })
    db.collection("products").document(product_id).set(doc)
    _decide(db, listing_id, status="MATCHED_MANUAL", product_id=product_id,
            reason="producto creado manualmente", action="PRODUCT_CREATED_FROM_LISTING")
    return product_id


def _format(listing: dict) -> str:
    price = listing.get("currentPriceCents")
    price_txt = f"S/ {price / 100:,.2f}" if price else "—"
    return (f"{listing['id']}\n    {listing.get('storeCode')} · {price_txt} · {listing.get('title', '')[:90]}\n"
            f"    sugerido: {listing.get('productId') or '—'} (puntuación {listing.get('matchScore')}, "
            f"{listing.get('matchReason') or ''})")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    p_list = sub.add_parser("list")
    p_list.add_argument("--status", default="PENDING_REVIEW", choices=["PENDING_REVIEW", "UNMATCHED", "REJECTED"])
    p_list.add_argument("--limit", type=int, default=50)
    for name in ("approve", "reject", "create"):
        sub.add_parser(name).add_argument("listing_id")
    p_assign = sub.add_parser("assign")
    p_assign.add_argument("listing_id")
    p_assign.add_argument("product_id")
    for p in sub.choices.values():
        add_target_args(p)
    args = parser.parse_args(argv)
    db = resolve_db(args)
    try:
        if args.command == "list":
            items = list_listings(db, args.status, args.limit)
            print(f"{len(items)} publicaciones con estado {args.status}:\n")
            for item in items:
                print(_format(item))
        elif args.command == "approve":
            print(f"Aprobada: asociada a {approve(db, args.listing_id)}")
        elif args.command == "assign":
            assign(db, args.listing_id, args.product_id)
            print(f"Asignada a {args.product_id}")
        elif args.command == "reject":
            reject(db, args.listing_id)
            print("Rechazada")
        elif args.command == "create":
            print(f"Producto creado: {create(db, args.listing_id)}")
    except ReviewError as exc:
        print(f"ERROR: {exc}")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
