"""Códigos de barras GTIN (EAN-8, UPC-A, EAN-13, GTIN-14).

Las tiendas publican el mismo código con distinta longitud: `740617338515` (UPC-A, 12 dígitos)
y `0740617338515` (EAN-13) son el mismo producto. Se guardan en forma canónica de 13 dígitos
(o 14 si el GTIN-14 no empieza con 0) para que coincidan entre tiendas.

La app repite esta regla en `mobile_app/lib/core/search_normalizer.dart` (`canonicalGtin`).
"""

from __future__ import annotations

import re

_VALID_LENGTHS = {8, 12, 13, 14}


def gtin_check_digit_ok(code: str) -> bool:
    """Valida el dígito verificador (módulo 10, pesos 3 y 1 desde la derecha)."""
    digits = [int(c) for c in code]
    body, check = digits[:-1], digits[-1]
    total = sum(d * (3 if i % 2 == 0 else 1) for i, d in enumerate(reversed(body)))
    return (10 - total % 10) % 10 == check


def canonical_gtin(raw: str | None) -> str | None:
    """Devuelve el GTIN canónico o `None` si el código no es válido."""
    if not raw:
        return None
    code = re.sub(r"[\s-]", "", str(raw))
    if not code.isdigit() or len(code) not in _VALID_LENGTHS or not gtin_check_digit_ok(code):
        return None
    if len(code) == 14:
        return code[1:] if code.startswith("0") else code
    return code.zfill(13)
