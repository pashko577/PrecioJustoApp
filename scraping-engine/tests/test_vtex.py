import json
from pathlib import Path

import pytest
from scrapy.exceptions import CloseSpider
from scrapy.http import Request, TextResponse
from scrapy.utils.test import get_crawler

from app.normalizers.price import number_to_cents
from app.spiders.vtex.registry import SPIDERS
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
    assert offers["90011"].identifiers == {"GTIN": "2001234567893", "MPN": "DBK14R5"}
    assert offers["90021"].identifiers == {}       # sin EAN ni referencia
    assert offers["90031"].identifiers == {"MPN": "DPX128"}  # EAN "12345" inválido se descarta


def test_default_seller_is_used_not_cheapest_marketplace_seller():
    offers, _ = all_offers()
    ssd = offers["90021"]
    assert ssd.seller is None  # vendedor "1" = la propia tienda (no se muestra como externo)
    assert ssd.price_cents == 20900  # no el precio del vendedor de marketplace


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
    CoolboxSpider = SPIDERS["coolbox"]
    assert CoolboxSpider.__name__ == "CoolboxSpider"
    assert CoolboxSpider.allowed_domains == ["www.coolbox.pe"]
    assert CoolboxSpider.categories["/47/258/259/"] == "ssd"
    assert CoolboxSpider.store_code == "COOLBOX"
    assert CoolboxSpider.base_url == "https://www.coolbox.pe"
    from app.catalog import flatten_categories
    valid = {c["slug"] for c in flatten_categories()}
    assert set(CoolboxSpider.categories.values()) <= valid
    assert 429 not in CoolboxSpider.custom_settings["RETRY_HTTP_CODES"]
    assert CoolboxSpider.custom_settings["DOWNLOAD_DELAY"] >= 3


# ---------- Títulos sin repeticiones ----------

from app.spiders.vtex.base import clean_title  # noqa: E402


def test_title_real_duplicate_case_from_coolbox():
    product = "Disco solido SSD Kingston A400, 480GB, SATA 6GBS, 25 7MM, negro"
    item = "Disco Solido SSD Kingston A400 480GB SATA 6GBS 25 7MM"
    assert clean_title(product, item, f"{product} {item}") == product


def test_title_same_names():
    assert clean_title("Celular Motorola G47", "Celular Motorola G47") == "Celular Motorola G47"


def test_title_short_variant_is_appended():
    assert clean_title("Laptop Demo Book 14", "Azul") == "Laptop Demo Book 14 - Azul"


def test_title_item_more_complete_wins():
    assert clean_title("MacBook Air 13", "MacBook Air 13 M4 16GB") == "MacBook Air 13 M4 16GB"


def test_title_fallbacks():
    assert clean_title("", "Solo variante") == "Solo variante"
    assert clean_title(None, None, "Nombre completo") == "Nombre completo"


def test_fixture_titles_use_variant_names():
    offers, _ = all_offers()
    assert offers["90011"].title == "Laptop Demo Book 14 Ryzen 5 16GB 512GB SSD - Gris"
    assert offers["90012"].title == "Laptop Demo Book 14 Ryzen 5 16GB 512GB SSD - Azul"


# ---------- Frecuencia por tienda ----------

def test_is_due():
    from datetime import datetime, timedelta, timezone

    from app.spiders.vtex.base import is_due
    now = datetime(2026, 11, 23, 12, tzinfo=timezone.utc)
    assert is_due(None, now)
    assert is_due({"scrapingIntervalMinutes": 720}, now)  # nunca corrió
    assert not is_due({"scrapingIntervalMinutes": 720, "lastCompleteRunAt": now - timedelta(hours=6)}, now)
    assert is_due({"scrapingIntervalMinutes": 720, "lastCompleteRunAt": now - timedelta(hours=11, minutes=30)}, now)
    assert is_due({"scrapingIntervalMinutes": 360, "lastCompleteRunAt": now - timedelta(hours=6)}, now)



# ---------- Código de fabricante real en VTEX ----------

def test_pick_mpn_prefers_real_model_code():
    from app.spiders.vtex.base import looks_like_model_code, pick_mpn
    # Coolbox: productReference es el modelo real
    assert pick_mpn({"productReference": "SA400S37960GB", "Modelo": ["SSD A400"]}) == "SA400S37960GB"
    # Intercorp: productReference es un correlativo; el modelo está en la especificación
    assert pick_mpn({"productReference": "2974961", "Modelo": ["RI-795DI"]}) == "RI-795DI"
    assert pick_mpn({"productReference": "20608011"}) is None
    assert pick_mpn({"productReference": "", "Modelo": ["Sin código"]}) is None
    assert looks_like_model_code("LS51BPP") and not looks_like_model_code("148753")


def test_internal_sellers_are_the_store_itself():
    from app.spiders.vtex.base import seller_name
    assert seller_name({"sellerId": "1", "sellerName": "CENCOSUD RETAIL PERU S.A."}) is None
    assert seller_name({"sellerId": "wongiononfood", "sellerName": "wongiononfood"}, ("wongio",)) is None
    assert seller_name({"sellerId": "lgperu", "sellerName": "LG Perú"}, ("wongio",)) == "LG Perú"


def test_commercial_names_are_not_manufacturer_codes():
    from app.spiders.vtex.base import looks_like_model_code, pick_mpn
    # Nombres comerciales: los comparten paquetes y variantes distintas.
    for name in ("PlayStation 5 Slim", "Switch 2", "Oled 2", "Galaxy A16", "PS5 DIGITAL BUNDLE 825GB"):
        assert not looks_like_model_code(name), name
    # Códigos internos de vendedores con fecha.
    assert not looks_like_model_code("GameCenter-1695497308512")
    # Códigos reales.
    for code in ("BEE-S-KB5NA", "CFI-2115", "RI-795DI", "LS51BPP", "82XB003MLM", "TWVS4001063-L"):
        assert looks_like_model_code(code), code
    assert pick_mpn({"productReference": "526487591245", "Modelo": ["Nintendo switch 2"]}) is None
