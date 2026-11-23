from scrapy.http import HtmlResponse, Request
from scrapy.utils.test import get_crawler

from app.spiders.demo_store.products import FIXTURE, DemoStoreSpider


def parse_fixture():
    crawler = get_crawler(DemoStoreSpider)
    spider = DemoStoreSpider.from_crawler(crawler)
    url = FIXTURE.as_uri()
    response = HtmlResponse(url=url, body=FIXTURE.read_bytes(), encoding="utf-8", request=Request(url))
    return spider, list(spider.parse(response))


def test_extracts_valid_offers_and_skips_broken_price():
    spider, offers = parse_fixture()
    assert [o.external_product_id for o in offers] == ["KNV3-1TB", "KNV3-2TB", "SAM-990-1TB"]
    assert spider.crawler.stats.get_value("offers/price_parse_failed") == 1
    assert spider.job_errors[0]["message"].startswith("BROKEN-1")


def test_offer_fields():
    _, offers = parse_fixture()
    knv3 = offers[0].validate()
    assert knv3.price_cents == 24990
    assert knv3.shipping_cents == 1000
    assert knv3.availability == "AVAILABLE"
    assert knv3.identifiers == {"ean": "0740617340456"}

    assert offers[1].price_cents == 124990
    assert offers[1].availability == "OUT_OF_STOCK"
    assert offers[1].shipping_cents is None  # sin dato = desconocido

    assert offers[2].availability == "PREORDER"
    assert offers[2].shipping_cents == 0  # la página dice "Gratis"


def test_all_offers_pass_contract():
    _, offers = parse_fixture()
    for offer in offers:
        offer.validate()
