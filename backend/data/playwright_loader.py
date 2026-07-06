"""Loads the multi-category listings fixture from disk.

Thin loader for tests and offline development. Live scraping is handled by
`live_loader.py`.
"""

import json
from pathlib import Path

_DATA_DIR = Path(__file__).resolve().parent
_FIXTURE_FILE = "listings_fixture.json"


def load_listings() -> list[dict]:
    fixture_path = _DATA_DIR / _FIXTURE_FILE
    with open(fixture_path, encoding="utf-8") as f:
        return json.load(f)
