"""Reglas del catálogo normalizado: categorías y documentos de producto (PRECIO_JUSTO.md, 9.3)."""

from __future__ import annotations

import json
import re
from dataclasses import dataclass, field
from pathlib import Path

from app.normalizers.identifiers import canonical_gtin
from app.normalizers.text import normalize_text, search_tokens

CATEGORIES_FILE = Path(__file__).resolve().parent / "data" / "categories.json"

# Productos sin precio verificado van al final al ordenar por precio (Firestore excluye
# documentos sin el campo y ordena los null primero, por eso se usa un valor centinela).
NO_PRICE_SORT_VALUE = 9_999_999_999

IDENTIFIER_TYPES = ("EAN", "GTIN", "UPC", "MPN")
BARCODE_TYPES = ("EAN", "GTIN", "UPC")
_SLUG_RE = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")


class CatalogError(ValueError):
    """Dato del catálogo inválido."""


def flatten_categories(tree: list[dict] | None = None) -> list[dict]:
    """Convierte el árbol de `categories.json` en documentos `categories/{slug}`."""
    if tree is None:
        tree = json.loads(CATEGORIES_FILE.read_text("utf-8"))
    result: list[dict] = []
    order = 0

    def walk(nodes: list[dict], parent: str | None) -> None:
        nonlocal order
        for node in nodes:
            order += 1
            result.append({
                "slug": node["slug"],
                "name": node["name"],
                "parentSlug": parent,
                "icon": node.get("icon"),
                "order": order,
                "description": node.get("description", ""),
                "status": "ACTIVE",
            })
            walk(node.get("children", []), node["slug"])

    walk(tree, None)
    slugs = [c["slug"] for c in result]
    duplicates = {s for s in slugs if slugs.count(s) > 1}
    if duplicates:
        raise CatalogError(f"Slugs de categoría duplicados: {sorted(duplicates)}")
    for c in result:
        if not _SLUG_RE.match(c["slug"]):
            raise CatalogError(f"Slug inválido: {c['slug']!r}")
    return result


def slugify(text: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", normalize_text(text)).strip("-")


def identifier_keys(identifiers: dict[str, list[str] | str] | None) -> list[str]:
    """Claves para buscar con `array-contains`.

    Los códigos de barras (EAN, UPC, GTIN) se unifican como `GTIN:<canónico de 13 dígitos>`,
    así UPC `740617338515` y EAN `0740617338515` coinciden. `MPN` (código del fabricante) se
    conserva tal cual.
    """
    keys: set[str] = set()
    for kind, values in (identifiers or {}).items():
        kind_up = kind.upper()
        if kind_up not in IDENTIFIER_TYPES:
            raise CatalogError(f"Tipo de identificador no soportado: {kind}")
        for value in [values] if isinstance(values, str) else values:
            clean = re.sub(r"[\s-]", "", str(value))
            if not clean:
                continue
            if kind_up in BARCODE_TYPES:
                gtin = canonical_gtin(clean)
                if gtin is None:
                    raise CatalogError(f"{kind_up} inválido (longitud o dígito verificador): {value!r}")
                keys.add(f"GTIN:{gtin}")
            else:
                keys.add(f"{kind_up}:{clean.upper()}")
    return sorted(keys)


@dataclass
class ProductInput:
    """Registro de producto para la carga inicial (`app/admin/import_products.py`)."""

    category: str
    brand: str
    model: str
    name: str
    id: str | None = None
    description: str = ""
    image_url: str | None = None
    condition: str = "NEW"
    attributes: dict[str, str] = field(default_factory=dict)
    identifiers: dict[str, list[str] | str] = field(default_factory=dict)


def build_product_doc(item: ProductInput, valid_categories: set[str]) -> tuple[str, dict]:
    """Valida un producto y devuelve `(id, campos)` para `products/{id}`.

    No incluye `summary`: el resumen de precios lo calcula el motor a partir de las ofertas.
    """
    errors = []
    if item.category not in valid_categories:
        errors.append(f"categoría desconocida: {item.category!r}")
    for field_name in ("brand", "model", "name"):
        if not str(getattr(item, field_name) or "").strip():
            errors.append(f"{field_name} vacío")
    if item.condition not in ("NEW", "REFURBISHED", "USED"):
        errors.append(f"condition inválida: {item.condition!r}")
    brand_in_name = normalize_text(item.brand) in normalize_text(item.name)
    product_id = item.id or slugify(item.name if brand_in_name else f"{item.brand} {item.name}")
    if not _SLUG_RE.match(product_id or ""):
        errors.append(f"id inválido: {product_id!r}")
    try:
        id_keys = identifier_keys(item.identifiers)
    except CatalogError as exc:
        errors.append(str(exc))
        id_keys = []
    if errors:
        raise CatalogError(f"{item.name or product_id}: " + "; ".join(errors))

    attributes = {normalize_text(k).replace(" ", "_"): normalize_text(str(v)) for k, v in item.attributes.items()}
    return product_id, {
        "categorySlug": item.category,
        "brand": item.brand.strip(),
        "model": item.model.strip(),
        "displayName": item.name.strip(),
        "normalizedName": normalize_text(item.name),
        "description": item.description.strip(),
        "imageUrl": item.image_url,
        "condition": item.condition,
        "status": "ACTIVE",
        "identifiers": {k.upper(): ([v] if isinstance(v, str) else list(v)) for k, v in item.identifiers.items()},
        "identifierKeys": id_keys,
        "attributes": attributes,
        "variants": [],
        "searchTokens": search_tokens(item.name, item.brand, item.model, *attributes.values()),
    }


def empty_summary() -> dict:
    """Resumen inicial de un producto sin ofertas."""
    return {
        "currency": "PEN",
        "minPriceCents": None,
        "minPriceStoreCode": None,
        "maxPriceCents": None,
        "sortPriceCents": NO_PRICE_SORT_VALUE,
        "offerCount": 0,
        "verifiedOfferCount": 0,
        "lastCheckedAt": None,
    }
