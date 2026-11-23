"""Foto del producto en un listado HTML (Magento, PrestaShop, Memory Kings)."""

from __future__ import annotations

import html as html_lib
import re

_IMG_RE = re.compile(r"<img\b[^>]*>", re.I)
# Carga diferida primero: en esos temas `src` es un marcador vacío (SVG en línea o 1x1).
_ATTRS = ("data-src", "data-original", "data-lazy", "src")
_ATTR_RE = {a: re.compile(rf'(?<![\w-]){a}="([^"]+)"', re.I) for a in _ATTRS}


def first_image_url(chunk: str, base_url: str | None = None) -> str | None:
    """URL absoluta de la primera imagen real del bloque de un producto, o None."""
    for tag in _IMG_RE.finditer(chunk):
        for attr in _ATTRS:
            match = _ATTR_RE[attr].search(tag.group(0))
            if not match:
                continue
            url = html_lib.unescape(match.group(1)).strip()
            if url.startswith("//"):
                url = "https:" + url
            elif url.startswith("/") and base_url:
                url = base_url.rstrip("/") + url
            if url.startswith(("https://", "http://")):
                return url
    return None
