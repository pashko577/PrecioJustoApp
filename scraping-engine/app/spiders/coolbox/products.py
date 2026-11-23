"""Coolbox (coolbox.pe) — tienda de tecnología sobre VTEX.

Evaluación (PRECIO_JUSTO.md, 7.7) — 23/11/2026:
- robots.txt: permite el catálogo público y /api/catalog_system/pub/*; bloquea /busca, carrito y cuenta.
- Términos y condiciones (RASH PERU S.R.L., actualización 21/09/2026): regulan compras; no contienen
  cláusulas sobre acceso automatizado ni extracción. Precios vigentes solo en coolbox.pe; fotos referenciales.
- La API de árbol de categorías respondió 429: se usan ids de categoría fijos y una pausa de 5 s.
- No se muestran las fotos de la tienda en la app (solo enlace).

Ejecutar:  scrapy crawl coolbox            (todas las categorías)
           scrapy crawl coolbox -a max_pages=1   (una página por categoría, para pruebas)
"""

from app.spiders.vtex.base import VtexSpider


class CoolboxSpider(VtexSpider):
    name = "coolbox"
    store_code = "COOLBOX"
    base_url = "https://www.coolbox.pe"
    allowed_domains = ["www.coolbox.pe"]
    categories = {
        "/47/65/": "laptops",            # Cómputo > Laptops
        "/171/626/": "laptops",          # Gamer > Laptops Gamer
        "/47/66/": "monitores",          # Cómputo > Monitores
        "/171/538/": "monitores",        # Gamer > Monitores Gamer
        "/47/258/259/": "ssd",           # Cómputo > Componentes > Discos Internos y SSD
        "/48/165/": "discos-externos",   # Almacenamiento > Discos externos
        "/20/21/": "celulares",          # Celulares y Accesorios > Celulares
    }
