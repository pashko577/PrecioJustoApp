"""Configuración de Scrapy para PRECIO JUSTO (extracción responsable, sección 7.7)."""

BOT_NAME = "precio_justo"
SPIDER_MODULES = ["app.spiders"]
NEWSPIDER_MODULE = "app.spiders"

# Identificación propia del cliente. Actualizar con la URL pública del proyecto cuando exista.
USER_AGENT = "PrecioJustoBot/0.1"

ROBOTSTXT_OBEY = True
CONCURRENT_REQUESTS_PER_DOMAIN = 1
DOWNLOAD_DELAY = 3
AUTOTHROTTLE_ENABLED = True
AUTOTHROTTLE_START_DELAY = 3
AUTOTHROTTLE_MAX_DELAY = 30
RETRY_TIMES = 2
COOKIES_ENABLED = False
MEMUSAGE_ENABLED = False  # Requiere el módulo resource (no existe en Windows)

ITEM_PIPELINES = {
    "app.pipelines.validation.ValidationPipeline": 100,
    "app.pipelines.firestore.FirestorePipeline": 300,
}

LOG_LEVEL = "INFO"
FEED_EXPORT_ENCODING = "utf-8"
