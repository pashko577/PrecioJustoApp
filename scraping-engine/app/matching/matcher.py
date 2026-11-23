"""Asocia publicaciones con productos del catálogo usando Firestore.

Para cuidar la cuota gratuita:
- Solo se intenta asociar publicaciones NUEVAS o todavía sin asociar (las ya asociadas se respetan).
- Los productos de cada categoría se leen una sola vez por corrida (caché en memoria).
- La búsqueda por código de barras consulta Firestore solo si no está en la caché.

Si una publicación con código de barras (GTIN) o código de fabricante (MPN) no coincide con
nada, se crea el producto: son identificadores confiables (nivel 1, sección 8.2). Sin ninguno
de los dos queda como UNMATCHED o PENDING_REVIEW para revisión manual (regla RN-06).
"""

from __future__ import annotations

from firebase_admin import firestore
from google.cloud.firestore_v1.base_query import FieldFilter

from app.catalog import CatalogError, ProductInput, build_product_doc, empty_summary, slugify
from app.normalizers.text import normalize_text, search_tokens
from app.matching.scoring import Candidate, Listing, MatchDecision, decide
from app.models.offer import ScrapedOffer

KEEP_STATUSES = {"MATCHED_AUTO", "MATCHED_MANUAL", "REJECTED", "PENDING_REVIEW"}


def candidate_from_doc(product_id: str, data: dict) -> Candidate:
    keys = data.get("identifierKeys", [])
    gtins = {k.split(":", 1)[1] for k in keys if k.startswith("GTIN:")}
    mpns = {k.split(":", 1)[1] for k in keys if k.startswith("MPN:")}
    return Candidate(
        product_id=product_id,
        name=data.get("displayName") or data.get("normalizedName") or product_id,
        brand=data.get("brand", ""),
        model=data.get("model", ""),
        condition=data.get("condition", "NEW"),
        gtins=gtins,
        mpns=mpns,
    )


class ProductMatcher:
    def __init__(self, db, valid_categories: set[str]):
        self.db = db
        self.valid_categories = valid_categories
        self._by_category: dict[str, dict[str, Candidate]] = {}
        self._by_key: dict[str, str] = {}  # "GTIN:..." / "MPN:..." -> product_id
        # Productos creados a partir de una publicación: "{storeCode}__{externalId}" -> product_id
        self._owned_by: dict[str, str] = {}
        self.renamed_products = 0
        self.created_products = 0

    def _load_category(self, slug: str) -> dict[str, Candidate]:
        if slug not in self._by_category:
            snaps = self.db.collection("products").where(filter=FieldFilter("categorySlug", "==", slug)).stream()
            loaded = {}
            for snap in snaps:
                data = snap.to_dict() or {}
                loaded[snap.id] = candidate_from_doc(snap.id, data)
                if source := data.get("source"):
                    self._owned_by[f"{source.get('storeCode')}__{source.get('externalProductId')}"] = snap.id
                for key in data.get("identifierKeys", []):
                    self._by_key[key] = snap.id
            self._by_category[slug] = loaded
        return self._by_category[slug]

    def _find_by_key(self, key: str) -> str | None:
        """Busca un producto por identificador (`GTIN:...` o `MPN:...`), primero en caché."""
        if key in self._by_key:
            return self._by_key[key]
        snaps = list(
            self.db.collection("products")
            .where(filter=FieldFilter("identifierKeys", "array_contains", key)).limit(1).stream()
        )
        if snaps:
            self._by_key[key] = snaps[0].id
            return snaps[0].id
        return None

    def match(self, offer: ScrapedOffer, existing: dict | None) -> MatchDecision:
        """Decide la asociación de una publicación. Respeta decisiones previas."""
        if existing and existing.get("matchStatus") in KEEP_STATUSES:
            return MatchDecision(existing.get("productId"), existing["matchStatus"], existing.get("matchScore"),
                                 existing.get("matchReason") or "decisión previa")

        gtin = offer.identifiers.get("GTIN")
        mpn = offer.identifiers.get("MPN")
        if gtin and (pid := self._find_by_key(f"GTIN:{gtin}")):
            return MatchDecision(pid, "MATCHED_AUTO", 100, "mismo código de barras")
        if mpn and (pid := self._find_by_key(f"MPN:{mpn}")):
            return MatchDecision(pid, "MATCHED_AUTO", 100, "mismo código de fabricante")

        slug = offer.category_hint if offer.category_hint in self.valid_categories else None
        if slug:
            listing = Listing(title=offer.title, brand=offer.brand, model=offer.model,
                              condition=offer.condition, gtin=gtin, mpn=mpn)
            decision = decide(listing, list(self._load_category(slug).values()))
            if decision.status != "UNMATCHED":
                return decision
            if gtin or mpn:
                pid = self._create_product(offer, slug)
                if pid:
                    return MatchDecision(pid, "MATCHED_AUTO", 100, "producto nuevo creado desde identificador")
            return decision
        return MatchDecision(None, "UNMATCHED", None, "sin categoría reconocida")

    def refresh_owned_name(self, offer: ScrapedOffer, product_id: str | None) -> bool:
        """Si el producto se creó desde ESTA publicación y su título cambió, actualiza el nombre.

        Corrige nombres creados con errores (por ejemplo, duplicados) sin intervención manual.
        Nunca toca productos creados desde otra tienda o cargados por un administrador.
        El pipeline solo la llama cuando el título de la publicación cambió: cuesta 1 lectura.
        """
        if not product_id:
            return False
        snap = self.db.collection("products").document(product_id).get()
        if not snap.exists:
            return False
        data = snap.to_dict() or {}
        source = data.get("source") or {}
        owner = f"{source.get('storeCode')}__{source.get('externalProductId')}"
        if owner != offer.doc_id or data.get("displayName") == offer.title:
            return False
        candidate = candidate_from_doc(product_id, data)
        self.db.collection("products").document(product_id).update({
            "displayName": offer.title,
            "normalizedName": normalize_text(offer.title),
            "searchTokens": search_tokens(offer.title, candidate.brand, candidate.model),
            "updatedAt": firestore.SERVER_TIMESTAMP,
        })
        cached = self._by_category.get(data.get("categorySlug", ""), {}).get(product_id)
        if cached:
            cached.name = offer.title
        self.renamed_products += 1
        return True

    def _create_product(self, offer: ScrapedOffer, slug: str) -> str | None:
        identifiers: dict[str, list[str]] = {}
        if gtin := offer.identifiers.get("GTIN"):
            identifiers["GTIN"] = [gtin]
        if mpn := offer.identifiers.get("MPN"):
            identifiers["MPN"] = [mpn]
        suffix = gtin or slugify(mpn or offer.external_product_id)
        base_id = slugify(f"{offer.brand or ''} {offer.model or offer.title}")[:80].strip("-") or slugify(offer.title)[:80]
        product_id = base_id
        if product_id in self._load_category(slug) or self.db.collection("products").document(product_id).get().exists:
            product_id = f"{base_id[:60]}-{suffix}"[:100].strip("-")
        try:
            _, data = build_product_doc(ProductInput(
                id=product_id,
                category=slug,
                brand=offer.brand or "Genérico",
                model=offer.model or "N/D",
                name=offer.title,
                condition=offer.condition,
                identifiers=identifiers,
            ), self.valid_categories)
        except CatalogError:
            return None
        data.update({
            "summary": empty_summary(),
            "source": {"storeCode": offer.store_code, "externalProductId": offer.external_product_id},
            "createdAt": firestore.SERVER_TIMESTAMP,
            "updatedAt": firestore.SERVER_TIMESTAMP,
        })
        self.db.collection("products").document(product_id).set(data)
        self._by_category.setdefault(slug, {})[product_id] = candidate_from_doc(product_id, data)
        self._owned_by[offer.doc_id] = product_id
        for key in data.get("identifierKeys", []):
            self._by_key[key] = product_id
        self.created_products += 1
        return product_id
