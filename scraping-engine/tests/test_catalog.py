import json

import pytest

from app.admin.import_products import load_products
from app.admin.seed import compute_summary
from app.catalog import (
    NO_PRICE_SORT_VALUE,
    CatalogError,
    ProductInput,
    build_product_doc,
    flatten_categories,
    identifier_keys,
    slugify,
)

VALID = {c["slug"] for c in flatten_categories()}


def test_categories_tree_from_document():
    cats = flatten_categories()
    top = [c for c in cats if c["parentSlug"] is None]
    assert len(top) == 12  # las 12 categorías de la sección 2.2
    slugs = {c["slug"] for c in cats}
    assert all(c["parentSlug"] in slugs for c in cats if c["parentSlug"])
    assert [c["order"] for c in cats] == sorted(c["order"] for c in cats)
    # Las categorías de los productos demo del sprint 1 siguen existiendo.
    assert {"ssd", "memorias-ram", "monitores"} <= slugs


def test_duplicate_category_slugs_rejected():
    with pytest.raises(CatalogError, match="duplicados"):
        flatten_categories([{"slug": "a", "name": "A", "children": [{"slug": "a", "name": "A2"}]}])


def test_slugify():
    assert slugify("Kingston NV3 1000 GB (Ñandú)") == "kingston-nv3-1tb-nandu"


def test_identifier_keys():
    assert identifier_keys({"ean": ["2001-2345 67893"], "MPN": "snv3s/1000g"}) == [
        "GTIN:2001234567893",
        "MPN:SNV3S/1000G",
    ]
    # UPC de 12 dígitos y EAN de 13 del mismo producto producen la misma clave.
    assert identifier_keys({"UPC": "740617338515"}) == identifier_keys({"EAN": "0740617338515"})
    with pytest.raises(CatalogError, match="verificador"):
        identifier_keys({"EAN": ["0740617340456"]})  # dígito verificador incorrecto
    with pytest.raises(CatalogError):
        identifier_keys({"EAN": ["ABC"]})
    with pytest.raises(CatalogError):
        identifier_keys({"SKU": ["1"]})


def test_build_product_doc():
    pid, doc = build_product_doc(
        ProductInput(category="ssd", brand="Kingston", model="NV3", name="Kingston NV3 1TB",
                     attributes={"Capacidad": "1000 GB"}, identifiers={"EAN": "2001234567893"}),
        VALID,
    )
    assert pid == "kingston-nv3-1tb"  # no repite la marca si ya está en el nombre
    pid2, _ = build_product_doc(ProductInput(category="ssd", brand="Kingston", model="NV3", name="SSD NV3 1TB"), VALID)
    assert pid2 == "kingston-ssd-nv3-1tb"
    assert doc["normalizedName"] == "kingston nv3 1tb"
    assert doc["attributes"] == {"capacidad": "1tb"}
    assert doc["identifierKeys"] == ["GTIN:2001234567893"]
    assert {"kingston", "kings", "nv3", "1tb"} <= set(doc["searchTokens"])
    assert "summary" not in doc  # el resumen lo calcula el motor


def test_build_product_doc_reports_all_errors():
    with pytest.raises(CatalogError) as exc:
        build_product_doc(ProductInput(category="inexistente", brand="", model="X", name="Algo",
                                       condition="SEMINUEVO"), VALID)
    message = str(exc.value)
    assert "categoría" in message and "brand" in message and "condition" in message


def test_sample_products_file_is_valid():
    from app.admin.seed import SAMPLE_PRODUCTS_FILE

    docs = load_products(SAMPLE_PRODUCTS_FILE, VALID)
    assert len(docs) >= 10


def test_load_products_rejects_duplicates_and_unknown_fields(tmp_path):
    f = tmp_path / "p.json"
    f.write_text(json.dumps([
        {"id": "a", "category": "ssd", "brand": "B", "model": "M", "name": "N"},
        {"id": "a", "category": "ssd", "brand": "B", "model": "M", "name": "N"},
        {"category": "ssd", "brand": "B", "model": "M", "name": "N", "precio": 10},
    ]), "utf-8")
    with pytest.raises(CatalogError) as exc:
        load_products(f, VALID)
    assert "#2" in str(exc.value) and "#3" in str(exc.value)


def test_summary_ignores_stale_and_unavailable_offers():
    summary = compute_summary([
        ("A", "1", 30000, "AVAILABLE", None, 2),
        ("B", "2", 10000, "AVAILABLE", None, 48),     # más barata pero desactualizada
        ("C", "3", 5000, "OUT_OF_STOCK", None, 1),    # más barata pero agotada
    ])
    assert summary["minPriceCents"] == 30000
    assert summary["sortPriceCents"] == 30000
    assert summary["verifiedOfferCount"] == 1


def test_summary_without_verified_offers_sorts_last():
    summary = compute_summary([("A", "1", 30000, "OUT_OF_STOCK", None, 2)])
    assert summary["minPriceCents"] is None
    assert summary["sortPriceCents"] == NO_PRICE_SORT_VALUE
