"""Utilidades compartidas por los extractores de tiendas de cómputo."""

from __future__ import annotations

import html as html_lib
import re

from app.normalizers.price import parse_price_to_cents

_SOLES_RE = re.compile(r"S/\.?[\s\xa0]*(\d[\d.,]*)")
_TAG_RE = re.compile(r"<[^>]+>")


def text(fragment: str | None) -> str:
    """Texto plano de un fragmento HTML, sin etiquetas y con espacios normalizados."""
    return " ".join(html_lib.unescape(_TAG_RE.sub(" ", fragment or "")).split())


def soles_cents(fragment: str | None) -> int | None:
    """Precio en soles de un texto como "S/. 1,579.00" o "$ 554.85 - (S/ 1,897.60)"."""
    match = _SOLES_RE.search(html_lib.unescape(fragment or ""))
    if not match:
        return None
    try:
        cents = parse_price_to_cents(match.group(1).rstrip(".,"))
    except ValueError:
        return None
    return cents if cents > 0 else None


def split_cards(page_html: str, marker: str) -> list[str]:
    """Bloques de producto que empiezan en `marker` (cada uno hasta el siguiente)."""
    starts = [m.start() for m in re.finditer(re.escape(marker), page_html)]
    return [page_html[s: starts[i + 1] if i + 1 < len(starts) else len(page_html)] for i, s in enumerate(starts)]
