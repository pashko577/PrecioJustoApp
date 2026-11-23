"""Normalización de texto y tokens de búsqueda (RF-02).

IMPORTANTE: la app Flutter repite esta misma normalización al buscar
(`mobile_app/lib/core/search_normalizer.dart`). Ambas se prueban contra los mismos
casos en `shared/test_vectors/search_normalization.json`. Si cambias algo aquí,
cambia también la versión Dart y agrega casos al archivo compartido.
"""

import re
import unicodedata

STOPWORDS = frozenset({"de", "del", "la", "el", "los", "las", "y", "con", "para", "en"})
MIN_WORD_LENGTH = 2
MIN_PREFIX_LENGTH = 3

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


def normalize_text(text: str | None) -> str:
    """Minúsculas, sin tildes, unidades unificadas ("1000 GB" -> "1tb") y espacios simples."""
    text = strip_accents(text or "").lower()
    text = _normalize_units(text)
    text = re.sub(r"[^a-z0-9.+\- ]", " ", text)
    return re.sub(r"\s+", " ", text).strip()


def word_tokens(*parts: str | None) -> list[str]:
    """Palabras normalizadas, únicas y ordenadas (sin prefijos). Se usan para comparar productos."""
    tokens: set[str] = set()
    for part in parts:
        for token in normalize_text(part).split(" "):
            token = token.strip(".-")
            if len(token) >= MIN_WORD_LENGTH and token not in STOPWORDS:
                tokens.add(token)
    return sorted(tokens)


def search_tokens(*parts: str | None) -> list[str]:
    """Tokens para el campo `products.searchTokens`: palabras + sus prefijos (desde 3 letras).

    Los prefijos permiten buscar palabras incompletas ("kings" encuentra "kingston").
    No se generan prefijos de números puros (por ejemplo, códigos EAN).
    """
    tokens: set[str] = set()
    for word in word_tokens(*parts):
        tokens.add(word)
        if not word.isdigit():
            for end in range(MIN_PREFIX_LENGTH, len(word)):
                tokens.add(word[:end])
    return sorted(tokens)
