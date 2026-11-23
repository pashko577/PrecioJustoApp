import json
from pathlib import Path

import pytest

from app.normalizers.text import normalize_text, search_tokens, word_tokens

VECTORS = json.loads(
    (Path(__file__).resolve().parents[2] / "shared" / "test_vectors" / "search_normalization.json").read_text("utf-8")
)["cases"]


@pytest.mark.parametrize("case", VECTORS, ids=[c["input"] or "<vacío>" for c in VECTORS])
def test_shared_vectors(case):
    """Mismos casos que prueba la app Flutter: garantiza que guardar y buscar normalizan igual."""
    assert normalize_text(case["input"]) == case["normalized"]
    assert word_tokens(case["input"]) == case["words"]


def test_different_capacities_produce_different_tokens():
    """Regla 8.3: no mezclar capacidades distintas."""
    assert "1tb" in word_tokens("Kingston NV3 1TB")
    assert "2tb" in word_tokens("Kingston NV3 2000 GB")
    assert "1tb" not in word_tokens("Kingston NV3 2000 GB")


def test_same_product_different_titles_share_key_words():
    a = set(word_tokens("Kingston SSD NV3 1TB"))
    b = set(word_tokens("Disco sólido Kingston NV3 de 1000 GB"))
    c = set(word_tokens("SSD Kingston 1TB PCIe 4.0 NV3"))
    assert {"kingston", "nv3", "1tb"} <= a & b & c


def test_word_tokens_are_sorted_and_unique():
    assert word_tokens("ssd SSD Ssd kingston", "Kingston") == ["kingston", "ssd"]


def test_search_tokens_include_prefixes_from_three_letters():
    tokens = search_tokens("Kingston")
    assert {"kin", "king", "kings", "kingst", "kingsto", "kingston"} <= set(tokens)
    assert "ki" not in tokens


def test_search_tokens_keep_short_words_but_do_not_prefix_numbers():
    tokens = search_tokens("LG 2001234567893")
    assert "lg" in tokens
    assert "2001234567893" in tokens
    assert "200" not in tokens


def test_search_tokens_contain_all_words():
    name = "Samsung 990 EVO Plus 1TB"
    assert set(word_tokens(name)) <= set(search_tokens(name))
