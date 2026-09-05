"""Shared listings cache between the scraper job and the agent API.

The scraper (CronJob or a one-off Job) is the only thing that runs
Playwright; it writes its scraped-and-valued results here. The API reads
this file on every /api/scan call instead of scraping live in the request
path, so the agent API image never needs Chromium.
"""
import json
import os
from pathlib import Path

_DEFAULT_CACHE_PATH = Path(__file__).resolve().parent / "listings_cache.json"


def _cache_path() -> Path:
    configured = os.environ.get("LISTINGS_CACHE_PATH")
    return Path(configured) if configured else _DEFAULT_CACHE_PATH


def read_listings_cache() -> list[dict]:
    path = _cache_path()
    if not path.exists():
        return []
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def write_listings_cache(listings: list[dict]) -> None:
    path = _cache_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(listings, f)
