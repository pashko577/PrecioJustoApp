import pytest

from app.normalizers.price import parse_price_to_cents


@pytest.mark.parametrize(
    ("raw", "expected"),
    [
        ("S/ 249.90", 24990),
        ("S/249.90", 24990),
        ("S/. 249.90", 24990),
        ("S/ 1,249.90", 124990),
        ("S/ 1.249,90", 124990),
        ("S/ 389", 38900),
        ("S/ 1,249", 124900),
        ("S/ 1.249", 124900),
        ("S/ 12,345,678.50", 1234567850),
        ("249,9", 24990),
        ("249.9", 24990),
        ("PEN 99.99", 9999),
        ("S/ 249.90", 24990),
    ],
)
def test_parse_price_to_cents(raw, expected):
    assert parse_price_to_cents(raw) == expected


def test_result_is_int_not_float():
    assert type(parse_price_to_cents("S/ 0.10")) is int


@pytest.mark.parametrize("raw", [None, "", "Consultar", "S/ -10", "S/ 0.00", "abc123"])
def test_invalid_prices_raise(raw):
    with pytest.raises(ValueError):
        parse_price_to_cents(raw)
