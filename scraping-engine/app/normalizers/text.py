"""Normalización de texto y generación de tokens de búsqueda (RF-02)."""

import re
import unicodedata

_STOPWORDS = {"de", "del", "la", "el", "los", "las", "y", "con", "para", "en"}
_UNIT_RE = re.compile(r"(\d+(?:[.,]\d+)?)\s*(tb|gb|mb|ghz|mhz|hz|w)\b", re.IGNORECASE)


def strip_accents(text: str) -> str:
    return "".join(c for c in unicodedata.normalize("NFD", text) if unicodedata.category(c) != "Mn")


def _normalize_units(text: str) -> str:
    def repl(match: re.Match) -> str:
        number, unit = match.group(1).replace(",", "."), match.group(2).lower()
        if unit == "gb" and "." not in number and int(number) >= 1000 and int(number) % 1000 == 0:
            return f"{int(number) // 1000}tb"
        if "." in number:
            number = number.rstrip("0").rstrip(".")
        return f"{number}{unit}"

    return _UNIT_RE.sub(repl, text)


def normalize_text(text: str) -> str:
    """Minúsculas, sin tildes, unidades unificadas ("1000 GB" -> "1tb") y espacios simples."""
    text = strip_accents(text or "").lower()
    text = _normalize_units(text)
    text = re.sub(r"[^a-z0-9.+\- ]", " ", text)
    return re.sub(r"\s+", " ", text).strip()


def search_tokens(*parts: str | None) -> list[str]:
    """Tokens únicos y ordenados para el campo `searchTokens` de Firestore."""
    tokens: set[str] = set()
    for part in parts:
        for token in normalize_text(part or "").split(" "):
            token = token.strip(".-")
            if len(token) >= 2 and token not in _STOPWORDS:
                tokens.add(token)
    return sorted(tokens)
