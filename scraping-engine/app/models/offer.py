"""Contrato de datos común a todos los extractores (PRECIO_JUSTO.md, sección 7.2)."""

from __future__ import annotations

from dataclasses import dataclass, field, asdict
from datetime import datetime, timezone

AVAILABILITY_VALUES = {"AVAILABLE", "OUT_OF_STOCK", "PREORDER", "UNKNOWN"}
CONDITION_VALUES = {"NEW", "REFURBISHED", "USED"}
CURRENCY_VALUES = {"PEN"}


class InvalidOfferError(ValueError):
    """La oferta extraída no cumple el contrato."""


@dataclass
class ScrapedOffer:
    store_code: str
    external_product_id: str
    title: str
    price_cents: int
    product_url: str
    currency: str = "PEN"
    availability: str = "UNKNOWN"
    condition: str = "NEW"
    brand: str | None = None
    model: str | None = None
    seller: str | None = None
    shipping_cents: int | None = None  # None = envío desconocido (RN-03), no gratis
    identifiers: dict[str, str] = field(default_factory=dict)
    image_url: str | None = None
    checked_at: datetime = field(default_factory=lambda: datetime.now(timezone.utc))

    def validate(self) -> "ScrapedOffer":
        errors: list[str] = []
        if not self.store_code or not self.store_code.isupper():
            errors.append("store_code debe estar en mayúsculas")
        if not self.external_product_id or "/" in self.external_product_id:
            errors.append("external_product_id vacío o con '/'")
        if not self.title or len(self.title) > 500:
            errors.append("title vacío o mayor a 500 caracteres")
        if type(self.price_cents) is not int or self.price_cents <= 0:
            errors.append("price_cents debe ser entero positivo")
        if self.shipping_cents is not None and (type(self.shipping_cents) is not int or self.shipping_cents < 0):
            errors.append("shipping_cents debe ser entero >= 0 o None")
        if self.currency not in CURRENCY_VALUES:
            errors.append(f"currency no soportada: {self.currency}")
        if self.availability not in AVAILABILITY_VALUES:
            errors.append(f"availability inválida: {self.availability}")
        if self.condition not in CONDITION_VALUES:
            errors.append(f"condition inválida: {self.condition}")
        if not self.product_url.startswith(("https://", "http://", "file://")):
            errors.append("product_url inválida")
        if self.checked_at.tzinfo is None:
            errors.append("checked_at debe tener zona horaria (UTC)")
        if errors:
            raise InvalidOfferError("; ".join(errors))
        return self

    @property
    def doc_id(self) -> str:
        """ID determinista `{storeCode}__{externalId}`: evita duplicados por tienda."""
        return f"{self.store_code}__{self.external_product_id}"

    def to_dict(self) -> dict:
        return asdict(self)
