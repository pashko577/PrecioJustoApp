"""Extractores de listados HTML: PrestaShop (SercoPlus) y Memory Kings."""

import pytest
from scrapy.exceptions import CloseSpider
from scrapy.http import HtmlResponse, Request
from scrapy.utils.test import get_crawler

from app.spiders.listing_base import is_challenge
from app.spiders.memorykings.base import MemoryKingsSpider, expand_specs
from app.spiders.memorykings.base import parse_listing as parse_mk
from app.spiders.memorykings.registry import SPIDERS as MK_SPIDERS
from app.spiders.prestashop.base import PrestaShopSpider, availability_from_stock, soles_cents
from app.spiders.prestashop.base import parse_listing as parse_ps
from app.spiders.prestashop.registry import SPIDERS as PS_SPIDERS


def ps_card(pid, title, price, stock="1", regular=None):
    regular_html = f'<span class="regular-price">{regular}</span>' if regular else ""
    return f'''
<article class="item  product-miniature js-product-miniature" data-id-product="{pid}" data-id-product-attribute="0">
  <div class="tvproduct-name product-title"><a href="https://tienda.example.com/x/{pid}-p.html"><h6 itemprop="name">{title}</h6></a></div>
  <div class="tvproduct-stock"><label class="label">Stock: </label><span class="value">{stock}</span></div>
  <div class="tvproduct-reference"><label class="label">Referencia: </label><span class="value">1095{pid}</span></div>
  <div class="product-price-and-shipping"><meta itemprop="mpn" content="1234" />{regular_html}<span class="price">{price}</span></div>
</article>
<div class="tvproduct-wrapper grid-2"><span class="price">$&nbsp;1,00</span></div>'''


PS_PAGE = f'''<html><head><script src="/cdn-cgi/challenge-platform/scripts/jsd/main.js"></script></head><body>
<div class="sidebar"><div class="product-title"><a href="https://tienda.example.com/m/9-x.html"><h6>MONITOR LATERAL</h6></a></div>
<span class="price">$ 96,10 (S/ 338,27)</span></div>
<div id="js-product-list">
{ps_card(1, "LAPTOP LENOVO LOQ 15IAX9, Intel Core i5-12450HX, 8GB DDR5, SSD 512GB", "$&nbsp;860,80&nbsp;(S/&nbsp;3.030,02)")}
{ps_card(2, "Laptop Chuwi CoreBook X, Intel Core i9-13900HK, SSD 1TB", "$ 735,80 (S/ 2.590,02)", stock="0",
         regular="$ 800,00 (S/ 2.816,00)")}
{ps_card(3, "LAPTOP SOLO EN DOLARES", "$ 500,00")}
{ps_card(4, "Laptop HP 15 reacondicionado", "$ 300,00 (S/ 1.056,00)", stock="Mayor a 10")}
</div>
<div>Mostrando 1-4 de 10 artículo(s)</div></body></html>'''


def test_prestashop_listing_takes_soles_and_ignores_sidebar():
    offers, warnings, total = parse_ps(PS_PAGE, store_code="SERCOPLUS", category_slug="laptops")
    by_id = {o.external_product_id: o for o in offers}
    assert set(by_id) == {"1", "2", "4"}  # el 3 no tiene precio en soles; el lateral no es del listado
    assert total == 10
    assert any("sin precio en soles" in w for w in warnings)
    assert by_id["1"].price_cents == 303002
    assert by_id["1"].product_url == "https://tienda.example.com/x/1-p.html"
    assert by_id["2"].list_price_cents == 281600
    assert by_id["1"].list_price_cents is None


def test_prestashop_stock_brand_condition_and_no_fake_mpn():
    offers, _, _ = parse_ps(PS_PAGE, store_code="SERCOPLUS", category_slug="laptops")
    by_id = {o.external_product_id: o for o in offers}
    assert by_id["1"].availability == "AVAILABLE"
    assert by_id["2"].availability == "OUT_OF_STOCK"
    assert by_id["4"].availability == "AVAILABLE"
    assert by_id["2"].brand == "Chuwi"  # no "Intel" (el procesador)
    assert by_id["4"].condition == "REFURBISHED"
    assert by_id["1"].identifiers == {}  # el itemprop mpn "1234" es de relleno
    for offer in offers:
        offer.validate()


def test_soles_and_stock_helpers():
    assert soles_cents("$ 680.00 ó S/ 2,366.00") == 236600
    assert soles_cents("$\xa0860,80&nbsp;(S/\xa03.030,02)") == 303002
    assert soles_cents("$ 500,00") is None
    assert availability_from_stock("> 10") == "AVAILABLE"
    assert availability_from_stock("&gt; 10") == "AVAILABLE"
    assert availability_from_stock("0 ") == "OUT_OF_STOCK"
    assert availability_from_stock(None) == "UNKNOWN"


def test_passive_cloudflare_script_is_not_a_challenge():
    assert not is_challenge(PS_PAGE)
    assert is_challenge("<html><title>Just a moment...</title><div id='cf-chl-widget'></div></html>")
    assert is_challenge('<script src="/cdn-cgi/challenge-platform/h/b/orchestrate/chl_page/v1"></script>')


MK_PAGE = '''<html><body>
<ul class="banners"><li><a href="/producto/999/laptop-banner"><img alt="banner"/></a></li></ul>
<div class="header-products"><div>Mostrando <b>3</b> productos</div></div>
<ul class="products flex grid-1-4">
 <li><div><a href="/producto/356243/laptop-core-5-hp-200-g2i"><div class="content"><div class="title">
   <h4>LAPTOP Core 5 120U HP 200 G2i 16|512|16" grafica Intel</h4></div>
   <div class="price-before">$ 752.00 ó S/ 2,616.50</div><div class="price">$ 680.00 ó S/ 2,366.00</div>
   <div class="stock">Stock: <b>> 10</b></div><div class="code">Código interno: <b>042626</b></div></div></a></div></li>
 <li><div><a href="/producto/372456/laptop-lenovo-thinkbook"><div class="content"><div class="title">
   <h4>LAPTOP Core 5 210H LENOVO ThinkBook 16 G9 IRL 16|1TB|16" grafica Intel</h4></div>
   <div class="price">$ 1,385.00 ó S/ 4,819.50</div><div class="stock">Stock: <b>0</b></div></div></a></div></li>
 <li><div><a href="/producto/111/sin-precio"><div class="content"><div class="title"><h4>Laptop sin precio</h4></div>
   </div></a></div></li>
</ul></body></html>'''


def test_memorykings_listing():
    offers, warnings, total = parse_mk(MK_PAGE, store_code="MEMORYKINGS", category_slug="laptops")
    by_id = {o.external_product_id: o for o in offers}
    assert set(by_id) == {"356243", "372456"}  # el banner no es parte de la grilla
    assert total == 3 and len(warnings) == 1
    hp = by_id["356243"]
    assert (hp.price_cents, hp.list_price_cents, hp.availability) == (236600, 261650, "AVAILABLE")
    assert hp.title == 'LAPTOP Core 5 120U HP 200 G2i 16GB 512GB 16" grafica Intel'
    assert hp.brand == "HP"
    assert hp.product_url == "https://www.memorykings.pe/producto/356243/laptop-core-5-hp-200-g2i"
    assert by_id["372456"].availability == "OUT_OF_STOCK"
    assert "16GB 1TB" in by_id["372456"].title
    for offer in offers:
        offer.validate()


def test_expand_specs_only_touches_spec_triplets():
    assert expand_specs('X 8|256|14"') == 'X 8GB 256GB 14"'
    assert expand_specs("Memoria 8|16 algo") == "Memoria 8|16 algo"
    assert expand_specs("A16 16|512|16") == 'A16 16GB 512GB 16"'


# ---------- Spiders (sin red) ----------

class DemoPS(PrestaShopSpider):
    name = "demo_ps"
    store_code = "DEMO_PS"
    base_url = "https://tienda.example.com"
    categories = {"/3-laptops": "laptops"}


class DemoMK(MemoryKingsSpider):
    name = "demo_mk"
    store_code = "DEMO_MK"
    base_url = "https://www.memorykings.pe"
    categories = {"/listados/1/a": "laptops", "/listados/2/b": "laptops"}


def run(spider, path, slug, body, status=200, page=1):
    req = spider.make_request(path, slug, page)
    resp = HtmlResponse(url=req.url, status=status, body=body.encode(), encoding="utf-8", request=req)
    return list(spider.parse_page(resp, **req.cb_kwargs))


def test_prestashop_pagination_uses_page_param():
    spider = DemoPS.from_crawler(get_crawler(DemoPS))
    results = run(spider, "/3-laptops", "laptops", PS_PAGE)
    nexts = [r for r in results if isinstance(r, Request)]
    assert len(nexts) == 1 and nexts[0].url == "https://tienda.example.com/3-laptops?page=2"


def test_memorykings_no_pagination_and_dedupe_across_listings():
    spider = DemoMK.from_crawler(get_crawler(DemoMK))
    first = run(spider, "/listados/1/a", "laptops", MK_PAGE)
    second = run(spider, "/listados/2/b", "laptops", MK_PAGE)  # mismos productos en otro listado
    assert not any(isinstance(r, Request) for r in first + second)
    assert len(first) == 2 and second == []


@pytest.mark.parametrize("status", [403, 429, 503])
def test_html_spiders_stop_on_block(status):
    spider = DemoMK.from_crawler(get_crawler(DemoMK))
    with pytest.raises(CloseSpider):
        run(spider, "/listados/1/a", "laptops", "blocked", status=status)
    assert spider.stopped_early


def test_registries_from_stores_json():
    serco = PS_SPIDERS["sercoplus"]
    assert serco.store_code == "SERCOPLUS" and serco.allowed_domains == ["sercoplus.com"]
    assert serco.categories["/3-laptops"] == "laptops"
    mk = MK_SPIDERS["memorykings"]
    assert mk.store_code == "MEMORYKINGS" and mk.allowed_domains == ["www.memorykings.pe"]
    assert all(path.startswith("/listados/") for path in mk.categories)
    assert not any("resultados" in path for path in mk.categories)  # bloqueado por robots.txt
    assert mk.custom_settings["DOWNLOAD_DELAY"] >= 5


# ---------- Infotec (otro tema PrestaShop) ----------

def infotec_card(pid, title, price, regular=None, disabled=False):
    regular_html = f'<span class="regular-price text-muted">{regular}</span>' if regular else ""
    dis = " disabled" if disabled else ""
    return f'''
<article class="product-miniature js-product-miniature" data-id-product="{pid}" data-id-product-attribute="0" >
 <div class="product-description"><h2 class="h3 product-title"> <a href="https://infotec.example/laptop/{pid}-x.html">{title}</a> </h2>
 <div class="product-brand text-muted"> <a href="https://infotec.example/laptop/{pid}-x.html">Lenovo</a></div>
 <div class="product-price-and-shipping"><a href="#"> <span  class="product-price" content="1899" aria-label="Precio"> {price} </span></a> {regular_html}</div>
 <div class="product-description-short">Marca : Lenovo Modelo : V15 Producto : Laptop</div>
 <button class="btn add-to-cart" data-button-action="add-to-cart" type="submit"{dis}>Comprar</button></div>
</article>'''


INFOTEC_PAGE = f'''<div id="js-product-list">
{infotec_card(10, "LAPTOP LENOVO IDEAPAD SLIM3 I3-N305 8GB 512GB SSD 15.6 FHD FREEDOS (82XB003MLM)", "S/. 1899", "S/. 2713")}
{infotec_card(11, "LAPTOP LENOVO V15 G4 AMN RYZEN 3-7320U 8GB LPDDR5 512GB SSD 15.6 FHD FREEDOS (...", "S/. 1789", disabled=True)}
</div><div>Mostrando 1-2 de 2 artículo(s)</div>'''


def test_infotec_theme_price_brand_and_part_number():
    offers, warnings, total = parse_ps(INFOTEC_PAGE, store_code="INFOTEC", category_slug="laptops")
    by_id = {o.external_product_id: o for o in offers}
    assert set(by_id) == {"10", "11"} and not warnings and total == 2
    slim = by_id["10"]
    assert (slim.price_cents, slim.list_price_cents, slim.brand) == (189900, 271300, "Lenovo")
    assert slim.identifiers == {"MPN": "82XB003MLM"} and slim.availability == "AVAILABLE"
    v15 = by_id["11"]
    # Título recortado: sin número de parte completo NO hay MPN (y nunca la serie "V15").
    assert v15.identifiers == {} and v15.title.endswith("FREEDOS")
    assert v15.availability == "OUT_OF_STOCK"


def test_magento_list_with_extra_classes():
    from app.spiders.magento.base import parse_listing as parse_mg
    page = '''<ol class="filterproducts products list items product-items">
<li class="item product product-item"><div class="product-item-info">
<a class="product-item-link" href="https://phantom.example/ps5.html">PlayStation 5 Slim Digital</a>
<div data-product-id="38618"></div>
<span data-price-amount="3799.9" data-price-type="finalPrice"></span>
<form data-role="tocart-form"></form></div></li></ol>'''
    offers, _, _ = parse_mg(page, store_code="PHANTOM", category_slug="consolas")
    assert len(offers) == 1 and offers[0].price_cents == 379990 and offers[0].brand == "Sony"


def test_store_crawl_delay_is_respected():
    from app.spiders.magento.registry import SPIDERS as MAGENTO
    assert MAGENTO["phantom"].custom_settings["DOWNLOAD_DELAY"] >= 10  # Crawl-delay: 10
    assert MAGENTO["efe"].custom_settings["DOWNLOAD_DELAY"] == 6
