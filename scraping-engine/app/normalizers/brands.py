"""Detección de marca en títulos de tiendas que no publican la marca como dato aparte."""

from __future__ import annotations

from app.normalizers.text import normalize_text

# Marcas frecuentes en tecnología, electrohogar y herramientas en Perú.
# Las de varias palabras van como texto normalizado ("black decker").
KNOWN_BRANDS = {
    "acer": "Acer", "advance": "Advance", "alcatel": "Alcatel", "amd": "AMD", "aoc": "AOC", "apple": "Apple",
    "asus": "Asus", "bauker": "Bauker", "black decker": "Black+Decker", "black+decker": "Black+Decker", "blackline": "Blackline",
    "bosch": "Bosch", "coldex": "Coldex", "crucial": "Crucial", "daewoo": "Daewoo", "dell": "Dell",
    "dewalt": "DeWalt", "electrolux": "Electrolux", "gigabyte": "Gigabyte", "haier": "Haier",
    "hisense": "Hisense", "honor": "Honor", "hp": "HP", "huawei": "Huawei", "imaco": "Imaco",
    "indurama": "Indurama", "infinix": "Infinix", "intel": "Intel", "kingston": "Kingston",
    "lenovo": "Lenovo", "lg": "LG", "mabe": "Mabe", "makita": "Makita", "midea": "Midea",
    "motorola": "Motorola", "msi": "MSI", "oppo": "Oppo", "oster": "Oster", "panasonic": "Panasonic",
    "philips": "Philips", "realme": "Realme", "samsung": "Samsung", "sole": "Sole", "sony": "Sony",
    "stanley": "Stanley", "tcl": "TCL", "teka": "Teka", "tecno": "Tecno", "toshiba": "Toshiba",
    "truper": "Truper", "vivo": "Vivo", "western digital": "Western Digital", "whirlpool": "Whirlpool",
    "xiaomi": "Xiaomi", "zte": "ZTE",
}


def detect_brand(title: str | None) -> str | None:
    """Primera marca conocida que aparece en el título (por posición), o `None`."""
    text = f" {normalize_text(title)} "
    best: tuple[int, str] | None = None
    for key, name in KNOWN_BRANDS.items():
        pos = text.find(f" {key} ")
        if pos >= 0 and (best is None or pos < best[0]):
            best = (pos, name)
    return best[1] if best else None
