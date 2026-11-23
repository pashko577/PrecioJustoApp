"""Base de pipelines: obtiene el spider desde el crawler (API recomendada de Scrapy 2.13+)."""


class CrawlerAwarePipeline:
    crawler = None

    @classmethod
    def from_crawler(cls, crawler):
        pipeline = cls()
        pipeline.crawler = crawler
        return pipeline

    @property
    def spider(self):
        return self.crawler.spider
