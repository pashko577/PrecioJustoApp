"""Extractores de tiendas de cómputo: Shopify (MM Store), WooCommerce (Miau), CGS, Banana Store,
Fabritec y «sitemap + ficha» (Unik). Muestras recortadas del HTML/JSON real de cada tienda."""

import json

import pytest
from scrapy.exceptions import CloseSpider
from scrapy.http import HtmlResponse, Request, TextResponse
from scrapy.utils.test import get_crawler

from app.spiders.shopify.base import parse_products as parse_shopify
from app.spiders.shopify.registry import SPIDERS as SHOPIFY
from app.spiders.sitemap_products.base import parse_product_page, sitemap_products
from app.spiders.sitemap_products.registry import SPIDERS as SITEMAP
from app.spiders.tiendas_pc.bananastore import parse_listing as parse_banana
from app.spiders.tiendas_pc.cgs import availability as cgs_availability
from app.spiders.tiendas_pc.cgs import parse_listing as parse_cgs
from app.spiders.tiendas_pc.fabritec import parse_response as parse_fabritec
from app.spiders.tiendas_pc.registry import SPIDERS as TIENDAS_PC
from app.spiders.woocommerce.base import parse_products as parse_woo
from app.spiders.woocommerce.registry import SPIDERS as WOOCOMMERCE

# ---------- Shopify (MM Store) ----------

SHOPIFY_JSON = json.dumps({"products": [
    {"id": 1, "title": "MOUSE LOGITECH G203 LIGHTSYNC | 8,000 DPI | RGB | NEGRO", "handle": "mouse-logitech-g203",
     "vendor": "LOGITECH", "images": [{"src": "https://cdn.shopify.com/g203.jpg"}],
     "variants": [{"id": 11, "title": "Default Title", "price": "89.00", "compare_at_price": "120.50",
                   "sku": "mms000293", "barcode": None, "available": True}]},
    {"id": 2, "title": "TECLADO REDRAGON KUMARA K552", "handle": "teclado-kumara", "vendor": "REDRAGON", "images": [],
     "variants": [{"id": 21, "title": "Negro", "price": "179.00", "compare_at_price": None,
                   "sku": "6950376750341", "available": True},
                  {"id": 22, "title": "Blanco", "price": "185.00", "compare_at_price": "180.00",
                   "sku": "x", "available": False}]},
    {"id": 3, "title": "SIN PRECIO", "handle": "x", "variants": [{"id": 31, "price": "0.00", "available": True}]},
]})


def test_shopify_variants_prices_and_barcode_only_gtin():
    offers, warnings, total = parse_shopify(SHOPIFY_JSON, store_code="MMSTORE", base_url="https://mm.example/es-pe",
                                            category_slug="mouse")
    by_id = {o.external_product_id: o for o in offers}
    assert set(by_id) == {"11", "21", "22"} and total is None and len(warnings) == 1
    g203 = by_id["11"]
    assert (g203.price_cents, g203.list_price_cents, g203.brand) == (8900, 12050, "LOGITECH")
    assert g203.identifiers == {}  # SKU interno: no identifica el producto entre tiendas
    assert g203.product_url == "https://mm.example/es-pe/products/mouse-logitech-g203"
    assert g203.title.startswith("MOUSE LOGITECH G203")  # sin " - Default Title"
    assert by_id["21"].identifiers == {"GTIN": "6950376750341"} and by_id["21"].title.endswith(" - Negro")
    assert by_id["21"].product_url.endswith("?variant=21")
    assert by_id["22"].availability == "OUT_OF_STOCK" and by_id["22"].list_price_cents is None


def test_shopify_asks_next_page_only_when_full():
    spider = SHOPIFY["mmstore"]()
    spider.crawler = get_crawler(type(spider))
    assert spider.page_url("teclados", 2).endswith("/collections/teclados/products.json?limit=250&page=2")
    response = TextResponse(url=spider.page_url("mouse", 1), body=SHOPIFY_JSON.encode(), encoding="utf-8",
                            request=Request(spider.page_url("mouse", 1)))
    results = list(spider.parse_page(response, path="mouse", slug="mouse", page=1))
    assert all(not isinstance(r, Request) for r in results)  # 3 de 250: no hay más páginas


# ---------- WooCommerce (Miau Gaming) ----------

def woo_product(pid, name, price, currency="PEN", stock=True, sku="", regular=None):
    return {"id": pid, "name": name, "sku": sku, "permalink": f"https://miau.example/product/{pid}/",
            "is_in_stock": stock, "brands": [{"name": "Gigabyte"}], "images": [{"src": "https://miau.example/i.png"}],
            "prices": {"price": price, "regular_price": regular or price, "currency_code": currency,
                       "currency_minor_unit": 2}}


def test_woocommerce_only_soles_and_minor_units():
    body = json.dumps([
        woo_product(1, "TARJETA DE VIDEO RTX 5060 8GB GIGABYTE EAGLE", "175000", regular="189900"),
        woo_product(2, "PROCESADOR EN DOLARES", "30000", currency="USD"),
        woo_product(3, "SSD KINGSTON NV3 1TB", "26900", stock=False, sku="SNV3S/1000G"),
    ])
    offers, warnings, _ = parse_woo(body, store_code="MIAU", category_slug="tarjetas-graficas")
    by_id = {o.external_product_id: o for o in offers}
    assert set(by_id) == {"1", "3"} and "USD" in warnings[0]
    assert (by_id["1"].price_cents, by_id["1"].list_price_cents, by_id["1"].brand) == (175000, 189900, "Gigabyte")
    assert by_id["3"].availability == "OUT_OF_STOCK" and by_id["3"].identifiers == {"MPN": "SNV3S/1000G"}
    assert WOOCOMMERCE["miau"]().page_url("138", 1).endswith(
        "/wp-json/wc/store/v1/products?category=138&per_page=100&page=1")


# ---------- CGS Computer ----------

def cgs_card(pid, name, price, old=None, stock="Stock: 7 Und"):
    old_html = f'<div class="product-price-old">S/. {old}</div>' if old else ""
    return f'''<div class="product text-center" style="height: 100%;"><div class="product-inner">
<div class="product-card product-sale" style="color: #fff;">{stock}</div>
<figure class="product-media"><img src="https://archivos.cgs.example/{pid}.png" alt="{name}" /></figure>
<a href="javascript:void(0);" class="product_favorite fav-btn-{pid}" data-id-product="{pid}"></a>
<div class="product-caption"><div class="product-name"> <a href="detalle/?p=NTQ=&amp;name=X">{name}</a> </div>
<div class="product-prices clearfix"><div class="product-price text-center" style="float: none;">S/. {price}</div>{old_html}</div>
</div></div></div>'''


CGS_PAGE = f'''<div class="showing-results">Mostrando 1-20 <span>de 48 resultados</span></div>
{cgs_card(54, "PROCESADOR INTEL I3 3240 OEM", "50.00", old="70.00")}
{cgs_card(86, "PROCESADOR INTEL CORE i5-14400 LGA1700", "890.00", stock="Sin Stock")}
<div class="cart-total">S/. 0.00</div>'''


def test_cgs_listing():
    offers, warnings, total = parse_cgs(CGS_PAGE, store_code="CGS", base_url="https://cgs.example", category_slug="procesadores")
    assert total == 48 and not warnings
    first, second = offers
    assert (first.external_product_id, first.price_cents, first.list_price_cents) == ("54", 5000, 7000)
    assert first.product_url == "https://cgs.example/productos/detalle/?p=NTQ=&name=X"
    assert first.availability == "AVAILABLE" and second.availability == "OUT_OF_STOCK"
    assert first.brand == "Intel" and first.image_url == "https://archivos.cgs.example/54.png"
    assert cgs_availability("Stock: +10 Unds") == "AVAILABLE" and cgs_availability("") == "UNKNOWN"
    spider = TIENDAS_PC["cgs"]()
    assert spider.page_url("p=OQ==&cat=Procesadores", 1) == "https://cgs-computer.pe/categorias/?p=OQ==&cat=Procesadores"
    assert spider.page_url("p=OQ==&cat=Procesadores", 2).endswith("&pag=Mg==")  # "2" en base64


# ---------- Banana Store ----------

def banana_card(pid, name, new, old=None, stock="10+ Und"):
    old_html = f'<div class="old-price text-danger">{old}</div><br>' if old else ""
    stock_html = f'<span class="badge"><i class="fas"></i>Stock: {stock}</span>' if stock else ""
    return f'''<div class="card-product style-img-border" data-marca-id="164">
<a href="https://banana.example/productos/detalle/{pid}-x" class="product-img"><img class="img-product" src="https://archivos.banana.example/{pid}.png"></a>
<a href="#;" class="box-icon add-to-cart" data-id="{pid}" data-precio="9.9" data-stock="50"></a>
<div class="card-product-info"><p class="caption">MEMORIA RAM</p>{stock_html}
<a href="https://banana.example/productos/detalle/{pid}-x" class="name-product body-md-2 link" title="{name}"> {name} </a>
<div class="price-wrap">{old_html}<div class="new-price price-text">{new}</div></div></div></div>'''


BANANA_PAGE = f'''<p> Mostrando <span class="fw-bold">1-16</span> de <span class="title-sidebar fw-bold">23</span> productos encontrados </p>
{banana_card(46194, "MEMORIA RAM PATRIOT VIPER 32GB DDR5", "$ 554.85 - (S/ 1,897.60)", old="$ 610.34 - (S/ 2,087.36)")}
{banana_card(46195, "MEMORIA RAM KINGSTON FURY 16GB", "$ 100.00 - (S/ 342.00)", stock="0 Und")}'''


def test_banana_listing_takes_soles():
    offers, warnings, total = parse_banana(BANANA_PAGE, store_code="BANANASTORE", category_slug="memorias-ram")
    assert total == 23 and not warnings
    viper, fury = offers
    assert (viper.external_product_id, viper.price_cents, viper.list_price_cents) == ("46194", 189760, 208736)
    assert viper.product_url == "https://banana.example/productos/detalle/46194-x"
    assert viper.availability == "AVAILABLE" and fury.availability == "OUT_OF_STOCK"
    assert viper.brand == "Patriot"
    spider = TIENDAS_PC["bananastore"]()
    assert spider.page_url("memoria-ram", 2).endswith("/categorias/detalle/memoria-ram/?cat=memoria-ram&pag=2")


# ---------- Fabritec ----------

def fabritec_card(pid, brand, name, price, sold_out=False):
    button = ('<a class="btn btn-cart disabled" href="javascript:">Sin stock</a>' if sold_out
              else '<a class="btn btn-cart" href="javascript:">Agregar</a>')
    return f'''<div class="col-6"> <div class="card-grid-style-3 mb-10" > <div class="card-grid-inner p-0">
<div class="tools"><a class="btn btn-quickview" href="#ModalQuickview" data-product-id="{pid}"></a></div>
<div class="image-box"><a href="https://fabritec.example/producto-interno/{pid}"><img src="https://fabritec.example/storage/{pid}.webp" alt="Ecom"></a></div>
<div class="info-righ"><a class="font-xs color-gray-500"
   href="https://fabritec.example/producto-interno/{pid}">{brand}</a><br>
<a class="color-brand-3 font-sm-bold titulo_producto_card text-ellipsis-2"
   href="https://fabritec.example/producto-interno/{pid}">{name}</a>
<div class="price-info d-flex"><strong class="font-lg-bold price-main">{price}</strong> <span class="price-line">$ 226.00</span></div>
<div class="box-btn-cart">{button}</div></div></div></div></div>'''


def test_fabritec_json_cards_part_number_and_pages():
    body = json.dumps({
        "html": fabritec_card(1198, "AMD", "Procesador AMD Ryzen 5 3500 OEM (100-100000050MPK) Socket AM4", "S/ 617.66")
        + fabritec_card(1200, "Intel", "Procesador OEM Intel Core i5-12400 (BX8071512400-OEM) LGA1700", "S/ 784.22",
                        sold_out=True),
        "pagination": '<a class="page-link" href="x?page=2" data-page="2"> 2 </a><a data-page="2">›</a>',
    })
    offers, warnings, total = parse_fabritec(body, store_code="FABRITEC", category_slug="procesadores")
    ryzen, intel = offers
    assert not warnings and total == 4  # 2 páginas de 2 tarjetas
    assert (ryzen.external_product_id, ryzen.price_cents, ryzen.brand) == ("1198", 61766, "AMD")
    assert ryzen.identifiers == {"MPN": "100100000050MPK"} and ryzen.model == "100-100000050MPK"
    assert ryzen.product_url == "https://fabritec.example/producto-interno/1198"
    # 10 dígitos seguidos: podría ser un código de barras; no se usa como código de fabricante.
    assert intel.identifiers == {} and intel.availability == "OUT_OF_STOCK"
    url = TIENDAS_PC["fabritec"]().page_url("9/30", 3)
    assert url.endswith("/ajax/public/products?page=3&has_category_context=true&categories%5B%5D=9&subcategories%5B%5D=30")


# ---------- Sitemap + ficha (Unik) ----------

SITEMAP_XML = '''<urlset>
<url><loc>https://unik.example/producto/procesador-amd-ryzen-5-7600x</loc></url>
<url><loc>https://unik.example/producto/teclado-gamer-teros-te-4072g</loc></url>
<url><loc>https://unik.example/producto/botella-tinta-epson-t504</loc></url>
<url><loc>https://unik.example/categoria/monitores/monitor-fhd</loc></url>
<url><loc>https://unik.example/producto/motherboard-con-procesador-core-i5</loc></url>
</urlset>'''

PATTERNS = {"^procesador": "procesadores", "^(placa-madre|motherboard)": "placas-madre", "^teclado": "teclados"}


def test_sitemap_picks_only_our_categories_in_order():
    found = sitemap_products(SITEMAP_XML, "/producto/", PATTERNS)
    assert found == [
        ("https://unik.example/producto/procesador-amd-ryzen-5-7600x", "procesadores"),
        ("https://unik.example/producto/teclado-gamer-teros-te-4072g", "teclados"),
        ("https://unik.example/producto/motherboard-con-procesador-core-i5", "placas-madre"),
    ]


def product_page(price="25.5", currency="PEN", availability="https://schema.org/InStock", sku="TE-4072G"):
    data = {"@context": "https://schema.org/", "@type": "Product", "name": "Teclado alámbrico gamer TEROS TE-4072G, USB",
            "image": ["https://unik.example/storage/1.webp"], "sku": sku, "brand": {"@type": "Brand", "name": "Teros"},
            "offers": {"@type": "Offer", "priceCurrency": currency, "price": price, "availability": availability}}
    return f'<html><head><script type="application/ld+json">{json.dumps(data, ensure_ascii=False)}</script></head></html>'


def test_product_page_from_schema_org():
    url = "https://unik.example/producto/teclado-gamer-teros-te-4072g"
    offer, problem = parse_product_page(product_page(), store_code="UNIK", url=url, category_slug="teclados")
    assert problem is None
    assert (offer.external_product_id, offer.price_cents, offer.brand) == ("teclado-gamer-teros-te-4072g", 2550, "Teros")
    assert offer.identifiers == {"MPN": "TE4072G"} and offer.availability == "AVAILABLE"
    assert offer.image_url == "https://unik.example/storage/1.webp"
    out, _ = parse_product_page(product_page(availability="https://schema.org/OutOfStock", sku="12345"),
                                store_code="UNIK", url=url, category_slug="teclados")
    assert out.availability == "OUT_OF_STOCK" and out.identifiers == {}  # SKU solo numérico: no es un código
    none, why = parse_product_page(product_page(currency="USD"), store_code="UNIK", url=url, category_slug="teclados")
    assert none is None and "USD" in why
    assert parse_product_page("<html></html>", store_code="UNIK", url=url, category_slug="teclados")[0] is None


def test_sitemap_spider_limits_products_in_test_runs():
    spider = SITEMAP["unik"](max_pages=1)
    spider.crawler = get_crawler(type(spider))
    spider.categories = PATTERNS
    response = TextResponse(url="https://unikstoreperu.com/sitemap.xml", body=SITEMAP_XML.encode(), encoding="utf-8",
                            request=Request("https://unikstoreperu.com/sitemap.xml"))
    requests = list(spider.parse_sitemap(response))
    assert [r.cb_kwargs["slug"] for r in requests] == ["procesadores", "teclados", "placas-madre"]


@pytest.mark.parametrize("spider_name", ["mmstore", "miau", "unik", "cgs", "bananastore", "fabritec"])
def test_new_stores_stop_on_block(spider_name):
    registry = {**SHOPIFY, **WOOCOMMERCE, **SITEMAP, **TIENDAS_PC}
    spider = registry[spider_name]()
    spider.crawler = get_crawler(type(spider))
    response = HtmlResponse(url=spider.base_url + "/x", status=403, body=b"<html>blocked</html>",
                            request=Request(spider.base_url + "/x"))
    with pytest.raises(CloseSpider):
        if spider_name == "unik":
            list(spider.parse_sitemap(response))
        else:
            list(spider.parse_page(response, path="x", slug="ssd", page=1))
    assert spider.stopped_early and spider.job_errors


def test_new_store_configs():
    assert SHOPIFY["mmstore"].allowed_domains == ["mmstoreperu.com"]
    assert SHOPIFY["mmstore"].base_url == "https://mmstoreperu.com/es-pe"
    assert SITEMAP["unik"].store_config["productPathPrefix"] == "/producto/"
    # Unik: robots.txt prohíbe URLs con "?": el extractor solo pide sitemap.xml y fichas sin consulta.
    assert all("?" not in pattern for pattern in SITEMAP["unik"].categories)
    for name in ("mmstore", "miau", "unik"):
        assert {**SHOPIFY, **WOOCOMMERCE, **SITEMAP}[name].custom_settings["DOWNLOAD_DELAY"] >= 4
    for name in ("cgs", "bananastore", "fabritec"):
        assert TIENDAS_PC[name].custom_settings["DOWNLOAD_DELAY"] >= 6
