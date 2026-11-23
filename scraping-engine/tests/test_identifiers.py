import pytest

from app.normalizers.identifiers import canonical_gtin, gtin_check_digit_ok


@pytest.mark.parametrize(
    ("raw", "expected"),
    [
        ("740617338515", "0740617338515"),     # UPC-A real (Kingston) -> EAN-13
        ("0740617338515", "0740617338515"),    # mismo producto como EAN-13
        ("00740617338515", "0740617338515"),   # mismo producto como GTIN-14
        ("4006381333931", "4006381333931"),    # EAN-13 de ejemplo de GS1
        ("96385074", "0000096385074"),         # EAN-8
        ("2001-2345 67893", "2001234567893"),  # ficticio (prefijo 200: uso interno)
    ],
)
def test_canonical_gtin(raw, expected):
    assert canonical_gtin(raw) == expected


@pytest.mark.parametrize("raw", [None, "", "0740617340456", "12345", "ABC1234567890", "123456789012345"])
def test_invalid_gtin(raw):
    assert canonical_gtin(raw) is None


def test_check_digit():
    assert gtin_check_digit_ok("4006381333931")
    assert not gtin_check_digit_ok("4006381333932")


def test_canonical_mpn_unifies_spacing():
    from app.normalizers.identifiers import canonical_mpn
    assert canonical_mpn("RX 280 PLUS") == canonical_mpn("rx-280-plus") == canonical_mpn("RX280PLUS") == "RX280PLUS"
    assert canonical_mpn("SNV3S/1000G") == "SNV3S/1000G"
    assert canonical_mpn("  ") is None and canonical_mpn(None) is None
