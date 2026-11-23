"""Valida cada oferta contra el contrato antes de guardarla."""

from scrapy.exceptions import DropItem

from app.models.offer import InvalidOfferError, ScrapedOffer
from app.pipelines.base import CrawlerAwarePipeline
from app.pipelines.job_errors import record_error


class ValidationPipeline(CrawlerAwarePipeline):
    def process_item(self, item, spider=None):
        if not isinstance(item, ScrapedOffer):
            raise DropItem(f"Item inesperado: {type(item).__name__}")
        try:
            item.validate()
        except InvalidOfferError as exc:
            self.crawler.stats.inc_value("offers/invalid")
            record_error(self.spider, "WARNING", str(exc), item.product_url)
            raise DropItem(str(exc)) from exc
        self.crawler.stats.inc_value("offers/valid")
        return item
