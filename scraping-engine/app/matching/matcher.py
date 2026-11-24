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

from datetime import datetime, timedelta

from firebase_admin import firestore
from google.cloud.firestore_v1.base_query import FieldFilter

from app.catalog import CatalogError, ProductInput, build_product_doc, empty_summary, slugify
from app.normalizers.text import normalize_text, search_tokens
from app.matching.scoring import Candidate, Listing, MatchDecision, decide
from app.models.offer import ScrapedOffer

KEEP_STATUSES = {"MATCHED_AUTO", "MATCHED_MANUAL", "REJECTED", "PENDING_REVIEW"}
# Una publicación sin pareja se vuelve a intentar cada 3 días (o antes si cambian su título o
# sus códigos): cada intento cuesta lecturas y la mayoría sigue sin pareja.
UNMATCHED_RETRY = timedelta(days=3)


def should_retry_unmatched(offer: ScrapedOffer, existing: dict, now: datetime) -> bool:
    if existing.get("title") != offer.title or (existing.get("identifiers") or {}) != offer.identifiers:
        return True
    attempted = existing.get("matchAttemptedAt")
    return attempted is None or now - attempted >= UNMATCHED_RETRY


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
        self.enriched_products = 0
        self.created_products = 0
        # Operaciones de Firestore estimadas (presupuesto diario del plan gratuito).
        self.reads = 0
        self.last_attempted = False
        self.writes = 0
        self._missing_keys: set[str] = set()  # identificadores ya buscados sin resultado
        self.created_docs: dict[str, dict] = {}  # productos nuevos aún sin guardar

    def _load_category(self, slug: str) -> dict[str, Candidate]:
        if slug not in self._by_category:
            snaps = self.db.collection("products").where(filter=FieldFilter("categorySlug", "==", slug)).stream()
            loaded = {}
            self.reads += 1  # una consulta cuesta al menos 1 lectura aunque no devuelva nada
            for snap in snaps:
                self.reads += 1
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
        if key in self._missing_keys:
            return None
        snaps = list(
            self.db.collection("products")
            .where(filter=FieldFilter("identifierKeys", "array_contains", key)).limit(1).stream()
        )
        self.reads += 1
        if snaps:
            self._by_key[key] = snaps[0].id
            return snaps[0].id
        self._missing_keys.add(key)
        return None

    def match(self, offer: ScrapedOffer, existing: dict | None) -> MatchDecision:
        """Decide la asociación de una publicación. Respeta decisiones previas."""
        self.last_attempted = False
        if existing and existing.get("matchStatus") in KEEP_STATUSES:
            return MatchDecision(existing.get("productId"), existing["matchStatus"], existing.get("matchScore"),
                                 existing.get("matchReason") or "decisión previa")
        if (existing and existing.get("matchStatus") == "UNMATCHED"
                and not should_retry_unmatched(offer, existing, offer.checked_at)):
            return MatchDecision(None, "UNMATCHED", existing.get("matchScore"),
                                 existing.get("matchReason") or "sin coincidencia")
        self.last_attempted = True

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

    def take_created(self, product_id: str | None) -> dict | None:
        """Documento del producto recién creado para esta publicación (lo guarda el pipeline)."""
        return self.created_docs.pop(product_id, None) if product_id else None

    def enrich_product_keys(self, offer: ScrapedOffer, product_id: str | None) -> str | None:
        """Agrega al producto asociado los identificadores de la oferta que todavía no tiene.

        Así, un producto creado con el código interno de una tienda también coincide después
        con el código de fabricante que publica otra. Si ese código ya pertenece a OTRO producto
        no se fusiona nada (RN-06): devuelve ese producto para marcarlo como posible duplicado.
        """
        if not product_id:
            return None
        keys = []
        if gtin := offer.identifiers.get("GTIN"):
            keys.append(f"GTIN:{gtin}")
        if mpn := offer.identifiers.get("MPN"):
            keys.append(f"MPN:{mpn}")
        new_keys = []
        for key in keys:
            owner = self._find_by_key(key)
            if owner is None:
                new_keys.append(key)
            elif owner != product_id:
                return owner  # mismo código en dos productos: revisión manual
        if new_keys:
            self.db.collection("products").document(product_id).update({
                "identifierKeys": firestore.ArrayUnion(new_keys),
                "updatedAt": firestore.SERVER_TIMESTAMP,
            })
            self.writes += 1
            for key in new_keys:
                self._by_key[key] = product_id
                self._missing_keys.discard(key)
            self.enriched_products += 1
        return None

    def refresh_owned_name(self, offer: ScrapedOffer, product_id: str | None) -> bool:
        """Si el producto se creó desde ESTA publicación y su título cambió, actualiza el nombre.

        Corrige nombres creados con errores (por ejemplo, duplicados) sin intervención manual.
        Nunca toca productos creados desde otra tienda o cargados por un administrador.
        El pipeline solo la llama cuando el título de la publicación cambió: cuesta 1 lectura.
        """
        if not product_id:
            return False
        snap = self.db.collection("products").document(product_id).get()
        self.reads += 1
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
        self.writes += 1
        self.renamed_products += 1
        return True

    def _exists(self, product_id: str) -> bool:
        self.reads += 1
        return self.db.collection("products").document(product_id).get().exists

    def _create_product(self, offer: ScrapedOffer, slug: str) -> str | None:
        identifiers: dict[str, list[str]] = {}
        if gtin := offer.identifiers.get("GTIN"):
            identifiers["GTIN"] = [gtin]
        if mpn := offer.identifiers.get("MPN"):
            identifiers["MPN"] = [mpn]
        suffix = gtin or slugify(mpn or offer.external_product_id)
        base_id = slugify(f"{offer.brand or ''} {offer.model or offer.title}")[:80].strip("-") or slugify(offer.title)[:80]
        product_id = base_id
        if product_id in self._load_category(slug) or self._exists(product_id):
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
        # No se escribe aquí: el pipeline lo guarda junto con su publicación y su resumen ya
        # calculado (2 escrituras por producto nuevo en vez de 4). Ver `take_created`.
        self.created_docs[product_id] = data
        self._by_category.setdefault(slug, {})[product_id] = candidate_from_doc(product_id, data)
        self._owned_by[offer.doc_id] = product_id
        for key in data.get("identifierKeys", []):
            self._by_key[key] = product_id
            self._missing_keys.discard(key)
        self.created_products += 1
        return product_id
