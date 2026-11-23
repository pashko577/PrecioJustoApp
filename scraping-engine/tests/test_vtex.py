import json
from pathlib import Path

import pytest
from scrapy.exceptions import CloseSpider
from scrapy.http import Request, TextResponse
from scrapy.utils.test import get_crawler

from app.normalizers.price import number_to_cents
from app.spiders.coolbox.products import CoolboxSpider
from app.spiders.vtex.base import PAGE_SIZE, VtexSpider, offers_from_product, parse_total

FIXTURE = json.loads((Path(__file__).parent / "fixtures" / "vtex_search.json").read_text("utf-8"))


def all_offers():
    result, warnings = [], []
    for product in FIXTURE:
        offers, warns = offers_from_product(product, store_code="DEMO_VTEX", category_slug="laptops")
        result += offers
        warnings += warns
    return {o.external_product_id: o for o in result}, warnings


def test_number_to_cents_avoids_float_errors():
    assert number_to_cents(2499.9) == 249990
    assert number_to_cents(0.1 + 0.2) == 30   # 0.30000000000000004 -> 30 céntimos
    assert number_to_cents("629") == 62900
    assert number_to_cents(0) is None
    assert number_to_cents(-5) is None
    assert number_to_cents(None) is None
    assert number_to_cents(True) is None
    assert number_to_cents("abc") is None


def test_parse_total():
    assert parse_total("0-49/130") == 130
    assert parse_total(b"50-99/130") == 130
    assert parse_total(None) is None
    assert parse_total("raro") is None


def test_one_offer_per_sku_and_skips_zero_price():
    offers, warnings = all_offers()
    assert set(offers) == {"90011", "90012", "90021", "90031"}
    assert any("90041" in w for w in warnings)  # precio 0 = no es un precio real


def test_price_list_price_and_availability():
    offers, _ = all_offers()
    gray, blue = offers["90011"], offers["90012"]
    assert gray.price_cents == 249990
    assert gray.list_price_cents == 299900         # precio "normal" de la tienda, aparte
    assert gray.availability == "AVAILABLE"
    assert blue.list_price_cents is None           # igual al precio: no hay descuento
    assert blue.availability == "OUT_OF_STOCK"
    assert gray.shipping_cents is None             # envío desconocido, nunca 0 por defecto


def test_identifiers_are_canonical():
    offers, _ = all_offers()
    assert offers["90011"].identifiers == {"GTIN": "2001234567893", "MPN": "DBK14-R5"}
    assert offers["90021"].identifiers == {}       # sin EAN ni referencia
    assert offers["90031"].identifiers == {"MPN": "DPX-128"}  # EAN "12345" inválido se descarta


def test_default_seller_is_used_not_cheapest_marketplace_seller():
    offers, _ = all_offers()
    ssd = offers["90021"]
    assert ssd.seller == "Tienda Demo S.A.C."
    assert ssd.price_cents == 20900


def test_refurbished_detected_from_category():
    offers, _ = all_offers()
    assert offers["90031"].condition == "REFURBISHED"
    assert offers["90011"].condition == "NEW"


def test_all_offers_pass_contract():
    offers, _ = all_offers()
    for offer in offers.values():
        offer.validate()


# ---------- Spider (sin red) ----------

class DemoVtexSpider(VtexSpider):
    name = "demo_vtex"
    store_code = "DEMO_VTEX"
    base_url = "https://tienda.example.com"
    categories = {"/47/65/": "laptops"}


def make_spider(**kwargs):
    crawler = get_crawler(DemoVtexSpider)
    return DemoVtexSpider.from_crawler(crawler, **kwargs)


def response(spider, offset=0, status=206, body=FIXTURE, total=4):
    request = spider.make_request("/47/65/", "laptops", offset)
    return TextResponse(
        url=request.url, status=status, body=json.dumps(body).encode(), encoding="utf-8",
        headers={"resources": f"{offset}-{offset + PAGE_SIZE - 1}/{total}"}, request=request,
    )


def run_parse(spider, resp):
    return list(spider.parse_page(resp, **resp.request.cb_kwargs))


def test_search_url_uses_category_filter_and_page_size():
    spider = make_spider()
    url = spider.search_url("/47/65/", 50)
    assert url.startswith("https://tienda.example.com/api/catalog_system/pub/products/search?")
    assert "fq=C%3A%2F47%2F65%2F" in url and "_from=50" in url and "_to=99" in url


def test_parse_page_yields_offers_and_stops_at_total():
    spider = make_spider()
    results = run_parse(spider, response(spider, total=4))
    assert len(results) == 4 and not any(isinstance(r, Request) for r in results)


def test_parse_page_requests_next_page_when_more_results():
    spider = make_spider()
    results = run_parse(spider, response(spider, total=130))
    next_requests = [r for r in results if isinstance(r, Request)]
    assert len(next_requests) == 1 and "_from=50" in next_requests[0].url


def test_max_pages_limits_pagination():
    spider = make_spider(max_pages="1")
    results = run_parse(spider, response(spider, total=130))
    assert not any(isinstance(r, Request) for r in results)


@pytest.mark.parametrize("status", [429, 403])
def test_stops_when_store_asks(status):
    spider = make_spider()
    with pytest.raises(CloseSpider):
        run_parse(spider, response(spider, status=status, body=[]))
    assert spider.stopped_early
    assert spider.job_errors[0]["severity"] == "ERROR"


def test_coolbox_configuration():
    assert CoolboxSpider.store_code == "COOLBOX"
    assert CoolboxSpider.base_url == "https://www.coolbox.pe"
    from app.catalog import flatten_categories
    valid = {c["slug"] for c in flatten_categories()}
    assert set(CoolboxSpider.categories.values()) <= valid
    assert 429 not in CoolboxSpider.custom_settings["RETRY_HTTP_CODES"]
    assert CoolboxSpider.custom_settings["DOWNLOAD_DELAY"] >= 3
