from app.normalizers.text import normalize_text, search_tokens


def test_normalize_removes_accents_and_case():
    assert normalize_text("Disco Sólido KINGSTON") == "disco solido kingston"


def test_units_are_unified():
    assert normalize_text("Kingston NV3 1000 GB") == "kingston nv3 1tb"
    assert normalize_text("Kingston NV3 1 TB") == "kingston nv3 1tb"
    assert normalize_text("RAM 16 GB 5600 MHz") == "ram 16gb 5600mhz"


def test_different_capacities_produce_different_tokens():
    """Regla 8.3: no mezclar capacidades distintas."""
    assert "1tb" in search_tokens("Kingston NV3 1TB")
    assert "2tb" in search_tokens("Kingston NV3 2000 GB")
    assert "1tb" not in search_tokens("Kingston NV3 2000 GB")


def test_same_product_different_titles_share_key_tokens():
    a = set(search_tokens("Kingston SSD NV3 1TB"))
    b = set(search_tokens("Disco sólido Kingston NV3 de 1000 GB"))
    c = set(search_tokens("SSD Kingston 1TB PCIe 4.0 NV3"))
    assert {"kingston", "nv3", "1tb"} <= a & b & c


def test_stopwords_and_short_tokens_removed():
    tokens = search_tokens("Disco de 1 TB para la PC")
    assert "de" not in tokens and "la" not in tokens and "para" not in tokens


def test_tokens_are_sorted_and_unique():
    tokens = search_tokens("ssd SSD Ssd kingston", "Kingston")
    assert tokens == sorted(set(tokens)) == ["kingston", "ssd"]
