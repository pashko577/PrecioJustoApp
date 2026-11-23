from pathlib import Path

import pytest
from scrapy.exceptions import CloseSpider
from scrapy.http import HtmlResponse, Request
from scrapy.utils.test import get_crawler

from app.normalizers.brands import detect_brand
from app.spiders.magento.base import MagentoSpider, parse_listing
from app.spiders.magento.registry import SPIDERS

FIXTURE = (Path(__file__).parent / "fixtures" / "magento_listing.html").read_text("utf-8")


def offers():
    result, warnings, total = parse_listing(FIXTURE, store_code="DEMO_MAG", category_slug="refrigeradoras")
    return {o.external_product_id: o for o in result}, warnings, total


def test_listing_parsed_with_total_and_warnings():
    by_id, warnings, total = offers()
    assert set(by_id) == {"1001", "1002", "1003"}
    assert total == 53
    assert any("sin precio" in w for w in warnings)


def test_prices_and_list_price():
    by_id, _, _ = offers()
    fridge = by_id["1001"]
    assert fridge.price_cents == 109900
    assert fridge.list_price_cents == 169900
    assert by_id["1002"].price_cents == 229990
    assert by_id["1002"].list_price_cents is None


def test_block_outside_list_does_not_leak_prices():
    by_id, _, _ = offers()
    assert by_id["1003"].price_cents == 59900  # no toma el S/ 0.01 del bloque "vistos recientemente"
    assert by_id["1003"].list_price_cents is None


def test_availability_condition_brand_and_mpn():
    by_id, _, _ = offers()
    assert by_id["1001"].availability == "AVAILABLE"
    assert by_id["1002"].availability == "OUT_OF_STOCK"
    assert by_id["1003"].condition == "REFURBISHED"
    assert by_id["1001"].brand == "Coldex"
    assert by_id["1002"].brand == "Lenovo"
    assert by_id["1001"].identifiers == {"MPN": "RX280PLUS"}  # sin espacios: coincide con otras tiendas
    assert by_id["1001"].shipping_cents is None
    for o in by_id.values():
        o.validate()


def test_detect_brand():
    assert detect_brand("Refrigeradora LG Multi Air Flow 215LT") == "LG"
    assert detect_brand("Taladro Black+Decker 600W") == "Black+Decker"
    assert detect_brand("Laptop HP 15 con mouse Logitech") == "HP"
    assert detect_brand("Producto genérico") is None
    # Primera marca por posición, no la primera de la lista
    assert detect_brand("Cargador Samsung compatible con Xiaomi") == "Samsung"


# ---------- Spider (sin red) ----------

class DemoMagento(MagentoSpider):
    name = "demo_magento"
    store_code = "DEMO_MAG"
    base_url = "https://tienda.example.com"
    categories = {"/electrohogar/refrigeradoras.html": "refrigeradoras"}


def run(spider, body: str, status=200, page=1):
    req = spider.make_request("/electrohogar/refrigeradoras.html", "refrigeradoras", page)
    resp = HtmlResponse(url=req.url, status=status, body=body.encode(), encoding="utf-8", request=req)
    return list(spider.parse_page(resp, **req.cb_kwargs))


def make(**kw):
    return DemoMagento.from_crawler(get_crawler(DemoMagento), **kw)


def test_pagination_uses_p_param_and_total():
    spider = make()
    results = run(spider, FIXTURE)
    nexts = [r for r in results if isinstance(r, Request)]
    assert len(nexts) == 1 and nexts[0].url.endswith("/electrohogar/refrigeradoras.html?p=2")
    assert "product_list_limit" not in nexts[0].url  # parámetro bloqueado por robots.txt


def test_stops_after_last_page():
    spider = make()
    results = run(spider, FIXTURE, page=14)  # 14 * 4 >= 53
    assert not any(isinstance(r, Request) for r in results)


def test_max_pages():
    spider = make(max_pages="1")
    assert not any(isinstance(r, Request) for r in run(spider, FIXTURE))


@pytest.mark.parametrize(("status", "body"), [
    (403, "Forbidden"),
    (429, "Too many"),
    (200, "<html><title>Just a moment...</title><div id='cf-chl-widget'></div></html>"),
])
def test_stops_on_block_or_challenge_without_evading(status, body):
    spider = make()
    with pytest.raises(CloseSpider):
        run(spider, body, status=status)
    assert spider.stopped_early and spider.job_errors[0]["severity"] == "ERROR"


def test_registry_builds_efe_and_curacao():
    assert {"efe", "lacuracao"} <= set(SPIDERS)
    efe = SPIDERS["efe"]
    assert efe.store_code == "EFE" and efe.allowed_domains == ["www.efe.com.pe"]
    assert efe.categories["/tecnologia/computacion/laptops.html"] == "laptops"
    assert efe.custom_settings["DOWNLOAD_DELAY"] >= 5
