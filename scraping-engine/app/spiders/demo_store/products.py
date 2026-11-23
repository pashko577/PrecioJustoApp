"""Spider de demostración: lee un HTML local ficticio (sin tiendas reales en el sprint 1).

Ejecutar:  scrapy crawl demo_store
"""

from __future__ import annotations

from pathlib import Path

import scrapy

from app.models.offer import ScrapedOffer
from app.normalizers.price import parse_price_to_cents
from app.pipelines.job_errors import record_error

FIXTURE = Path(__file__).resolve().parents[3] / "tests" / "fixtures" / "demo_store.html"

AVAILABILITY_MAP = {
    "in_stock": "AVAILABLE",
    "out_of_stock": "OUT_OF_STOCK",
    "preorder": "PREORDER",
}


class DemoStoreSpider(scrapy.Spider):
    name = "demo_store"
    store_code = "DEMO_STORE"
    start_urls = [FIXTURE.as_uri()]

    def parse(self, response):
        for card in response.css("article.product"):
            sku = card.attrib.get("data-sku")
            url = card.css("a.product-link::attr(href)").get()
            raw_price = card.css(".price::text").get()

            try:
                price_cents = parse_price_to_cents(raw_price)
            except ValueError as exc:
                self.crawler.stats.inc_value("offers/price_parse_failed")
                record_error(self, "WARNING", f"{sku}: {exc}", url)
                continue

            yield ScrapedOffer(
                store_code=self.store_code,
                external_product_id=sku,
                title=(card.css(".product-title::text").get() or "").strip(),
                brand=card.css(".brand::text").get(),
                price_cents=price_cents,
                shipping_cents=self._parse_shipping(card.css(".shipping::text").get()),
                availability=AVAILABILITY_MAP.get(card.css(".stock::attr(data-status)").get(), "UNKNOWN"),
                identifiers={"ean": ean} if (ean := card.css(".ean::text").get()) else {},
                product_url=url,
                image_url=card.css("img.thumb::attr(src)").get(),
                seller="Tienda Demo",
            )

    @staticmethod
    def _parse_shipping(raw: str | None) -> int | None:
        """None = envío desconocido. "Gratis" = 0 solo si la página lo dice explícitamente."""
        if raw is None:
            return None
        if raw.strip().lower() == "gratis":
            return 0
        try:
            return parse_price_to_cents(raw)
        except ValueError:
            return None
