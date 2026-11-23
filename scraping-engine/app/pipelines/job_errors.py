"""Errores de una ejecución: se guardan como máximo 50 en `scrapingJobs.errors`."""

MAX_JOB_ERRORS = 50


def record_error(spider, severity: str, message: str, url: str | None = None) -> None:
    errors = getattr(spider, "job_errors", None)
    if errors is None:
        errors = spider.job_errors = []
    if len(errors) < MAX_JOB_ERRORS:
        errors.append({"severity": severity, "message": message[:500], "url": url})
