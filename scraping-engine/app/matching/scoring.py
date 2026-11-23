"""Puntuación de coincidencia entre una publicación y un producto (PRECIO_JUSTO.md, sección 8).

Funciones puras (sin Firestore) para poder probarlas a fondo.

| Criterio               | Puntos |
|------------------------|--------|
| Marca                  | 20     |
| Modelo                 | 30     |
| Características        | 30     |
| Capacidad o variante   | 15     |
| Identificador (GTIN)   | 5      |

Umbrales: >= 90 asociación automática; 75–89 revisión manual; < 75 sin coincidencia.
Las reglas bloqueantes (8.3) se evalúan antes y anulan la puntuación.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field

from app.normalizers.text import normalize_text, word_tokens

AUTO_MATCH_THRESHOLD = 90
REVIEW_THRESHOLD = 75

# Números que distinguen variantes: capacidad, frecuencia de refresco y potencia.
_CAPACITY_RE = re.compile(r"^\d+(?:\.\d+)?(?:tb|gb|mb|hz|w)$")
# "pcie4.0" -> "pcie" + "4.0" (las tiendas escriben estas versiones juntas o separadas).
_JOINED_VERSION_RE = re.compile(r"^(pcie|usb|gen|wifi|hdmi|dp|bt|bluetooth)(\d+(?:\.\d+)?)$")
# Palabras descriptivas que no son características técnicas (no suman ni restan).
_GENERIC_WORDS = {
    "disco", "solido", "unidad", "estado", "interno", "interna", "nuevo", "nueva", "original",
    "producto", "equipo", "modelo", "marca", "version", "capacidad", "almacenamiento", "memoria",
}
_PACK_WORDS = {"pack", "kit", "combo", "bundle", "x2", "x3", "2x", "3x", "duo", "trio", "set"}
_COLOR_WORDS = {
    "negro", "blanco", "gris", "plata", "plateado", "dorado", "azul", "rojo", "verde", "rosado",
    "morado", "lila", "amarillo", "naranja", "celeste", "grafito", "titanio", "midnight", "black",
    "white", "silver", "gold", "blue", "red", "green", "pink", "purple",
}


@dataclass
class Listing:
    """Lo que se sabe de una publicación de tienda."""

    title: str
    brand: str | None = None
    model: str | None = None
    condition: str = "NEW"
    gtin: str | None = None
    mpn: str | None = None
    words: list[str] = field(default_factory=list)

    def __post_init__(self):
        if not self.words:
            self.words = word_tokens(self.title, self.brand, self.model)


@dataclass
class Candidate:
    """Lo que se sabe de un producto del catálogo."""

    product_id: str
    name: str
    brand: str
    model: str = ""
    condition: str = "NEW"
    gtins: set[str] = field(default_factory=set)
    mpns: set[str] = field(default_factory=set)
    words: list[str] = field(default_factory=list)

    def __post_init__(self):
        if not self.words:
            self.words = word_tokens(self.name, self.brand, self.model)


def expand_versions(words: set[str]) -> set[str]:
    result = set()
    for w in words:
        m = _JOINED_VERSION_RE.match(w)
        result.update((m.group(1), m.group(2)) if m else (w,))
    return result


def model_codes(words: set[str] | list[str]) -> set[str]:
    """Tokens con letras y dígitos que parecen códigos de modelo ("ls51bpp", "ri-795di").

    Excluye capacidades/unidades ("1tb", "180hz") y tokens cortos.
    """
    return {w.replace("-", "") for w in words
            if len(w.replace("-", "")) >= 5 and re.search(r"[a-z]", w) and re.search(r"\d", w)
            and not _CAPACITY_RE.match(w) and not _JOINED_VERSION_RE.match(w)}


def capacities(words: list[str]) -> set[str]:
    return {w for w in words if _CAPACITY_RE.match(w)}


def blocking_reason(listing: Listing, candidate: Candidate) -> str | None:
    """Regla 8.3: casos que nunca se asocian automáticamente."""
    if listing.gtin and candidate.gtins and listing.gtin not in candidate.gtins:
        return "código de barras distinto"
    if listing.condition != candidate.condition:
        return "condición distinta (nuevo/reacondicionado)"
    cap_l, cap_c = capacities(listing.words), capacities(candidate.words)
    if cap_l and cap_c and cap_l != cap_c:
        return f"capacidad distinta ({sorted(cap_l)} vs {sorted(cap_c)})"
    pack_l, pack_c = bool(_PACK_WORDS & set(listing.words)), bool(_PACK_WORDS & set(candidate.words))
    if pack_l != pack_c:
        return "paquete vs. unidad"
    color_l, color_c = _COLOR_WORDS & set(listing.words), _COLOR_WORDS & set(candidate.words)
    if color_l and color_c and not (color_l & color_c):
        return "color distinto"
    return None


def score(listing: Listing, candidate: Candidate) -> int:
    """Puntuación 0–100 (sin aplicar reglas bloqueantes)."""
    points = 0
    l_words, c_words = set(listing.words), set(candidate.words)

    if listing.brand and normalize_text(listing.brand) == normalize_text(candidate.brand):
        points += 20

    model_words = set(word_tokens(candidate.model)) - set(word_tokens(candidate.brand))
    if (model_words and model_words <= l_words) or (model_codes(c_words) & model_codes(l_words)):
        points += 30  # modelo declarado contenido en el título, o código de modelo compartido

    # Características: se compara contra el conjunto MÁS PEQUEÑO. Un título corto que omite
    # características ("Kingston SSD NV3 1TB") no se castiga; uno que trae otras distintas, sí.
    ignore = (set(word_tokens(candidate.brand)) | model_words | capacities(candidate.words)
              | capacities(listing.words) | _GENERIC_WORDS)
    c_features, l_features = expand_versions(c_words) - ignore, expand_versions(l_words) - ignore
    smaller = min(len(c_features), len(l_features))
    if smaller:
        points += round(30 * len(c_features & l_features) / smaller)
    else:
        points += 30  # no hay características que contrastar

    cap_l, cap_c = capacities(listing.words), capacities(candidate.words)
    if cap_l == cap_c:
        points += 15

    if listing.gtin and listing.gtin in candidate.gtins:
        points += 5
    return min(points, 100)


@dataclass
class MatchDecision:
    product_id: str | None
    status: str          # MATCHED_AUTO | PENDING_REVIEW | UNMATCHED
    score: int | None
    reason: str = ""


def decide(listing: Listing, candidates: list[Candidate]) -> MatchDecision:
    """Elige el mejor candidato respetando bloqueos y umbrales."""
    if listing.gtin:
        for c in candidates:
            if listing.gtin in c.gtins and blocking_reason(listing, c) is None:
                return MatchDecision(c.product_id, "MATCHED_AUTO", 100, "mismo código de barras")
    if listing.mpn:
        for c in candidates:
            if listing.mpn in c.mpns and blocking_reason(listing, c) is None:
                return MatchDecision(c.product_id, "MATCHED_AUTO", 100, "mismo código de fabricante")

    best: tuple[int, Candidate] | None = None
    for c in candidates:
        if blocking_reason(listing, c):
            continue
        s = score(listing, c)
        if best is None or s > best[0]:
            best = (s, c)

    if best and best[0] >= AUTO_MATCH_THRESHOLD:
        return MatchDecision(best[1].product_id, "MATCHED_AUTO", best[0], "puntuación alta")
    if best and best[0] >= REVIEW_THRESHOLD:
        return MatchDecision(best[1].product_id, "PENDING_REVIEW", best[0], "coincidencia probable")
    return MatchDecision(None, "UNMATCHED", best[0] if best else None, "sin candidato suficiente")
