"""Conversión de precios en texto a céntimos enteros (nunca float)."""

from decimal import Decimal, InvalidOperation
import re

_CURRENCY_TOKENS = re.compile(r"(S/\.?|PEN|USD|US\$|\$|soles?)", re.IGNORECASE)


def parse_price_to_cents(raw: str) -> int:
    """Convierte textos como "S/ 1,249.90", "S/1.249,90" o "249" a céntimos.

    Reglas:
    - Si hay "." y ",", el último separador que aparece es el decimal.
    - Si solo hay un separador, aparece una vez y le siguen 1 o 2 dígitos, es decimal.
    - En cualquier otro caso, los separadores son de miles.
    """
    if raw is None:
        raise ValueError("Precio vacío")
    text = _CURRENCY_TOKENS.sub("", str(raw)).replace(" ", "").replace(" ", "").strip()
    if not text or not re.fullmatch(r"[\d.,]+", text):
        raise ValueError(f"Precio no reconocido: {raw!r}")

    last_dot, last_comma = text.rfind("."), text.rfind(",")
    if last_dot >= 0 and last_comma >= 0:
        decimal_sep = "." if last_dot > last_comma else ","
    elif last_dot >= 0 or last_comma >= 0:
        sep = "." if last_dot >= 0 else ","
        decimals = text.split(sep)[-1]
        decimal_sep = sep if text.count(sep) == 1 and len(decimals) in (1, 2) else None
    else:
        decimal_sep = None

    if decimal_sep:
        thousands_sep = "," if decimal_sep == "." else "."
        normalized = text.replace(thousands_sep, "").replace(decimal_sep, ".")
    else:
        normalized = text.replace(".", "").replace(",", "")

    try:
        value = Decimal(normalized)
    except InvalidOperation as exc:
        raise ValueError(f"Precio no reconocido: {raw!r}") from exc

    cents = int((value * 100).quantize(Decimal("1")))
    if cents <= 0:
        raise ValueError(f"Precio no positivo: {raw!r}")
    return cents


def number_to_cents(value: float | int | str | Decimal | None) -> int | None:
    """Convierte un precio numérico de una API (por ejemplo, `629.0` de VTEX) a céntimos.

    Pasa por `str` antes de `Decimal` para no arrastrar errores de punto flotante
    (`Decimal(0.1)` != `Decimal("0.1")`). Devuelve `None` si el valor no es un precio positivo.
    """
    if value is None or isinstance(value, bool):
        return None
    try:
        amount = Decimal(str(value))
    except InvalidOperation:
        return None
    if not amount.is_finite() or amount <= 0:
        return None
    return int((amount * 100).quantize(Decimal("1")))
