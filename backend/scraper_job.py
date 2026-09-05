"""Entrypoint for the scraper image: a small always-on FastAPI service (a
k8s Deployment, not a CronJob/Job) so the agent API can trigger a scrape
on demand — e.g. a "Scrape now" button in the webapp — instead of only
ever reading whatever the last scheduled run happened to write.

Scrapes live listings, estimates resale value, and — unlike the old
request-path flow this replaced — fetches an image for every listing
(not just the post-filter queue), since a scrape here never blocks a
user's own request. Writes the result to the shared cache the agent API
reads from.

A background thread still runs the same scrape on a fixed interval, so
the cache keeps refreshing even if nobody clicks the button.
"""
import logging
import os
import threading
import time
from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException

from backend.data.cache import write_listings_cache
from backend.data.live_loader import attach_images, load_listings

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Matches the old CronJob's `*/30 * * * *` cadence.
AUTO_SCRAPE_INTERVAL_SECONDS = int(os.environ.get("AUTO_SCRAPE_INTERVAL_SECONDS", 30 * 60))

_scrape_lock = threading.Lock()


def run_scrape() -> int:
    """Scrape, value, and cache listings. Returns the listing count.

    Non-blocking on the lock: raises RuntimeError if a scrape is already
    in flight (either the background schedule or another on-demand
    trigger), rather than running two Playwright sessions at once.
    """
    if not _scrape_lock.acquire(blocking=False):
        raise RuntimeError("a scrape is already running")
    try:
        listings = load_listings()
        listings = attach_images(listings)
        write_listings_cache(listings)
        logger.info("wrote %d listings to cache", len(listings))
        return len(listings)
    finally:
        _scrape_lock.release()


def _auto_scrape_loop() -> None:
    while True:
        time.sleep(AUTO_SCRAPE_INTERVAL_SECONDS)
        try:
            run_scrape()
        except RuntimeError:
            logger.info("skipping scheduled scrape — one is already running")
        except Exception:
            logger.exception("scheduled scrape failed")


@asynccontextmanager
async def lifespan(app: FastAPI):
    threading.Thread(target=_auto_scrape_loop, daemon=True).start()
    yield


app = FastAPI(lifespan=lifespan)


@app.post("/scrape")
def scrape():
    try:
        count = run_scrape()
    except RuntimeError as exc:
        raise HTTPException(status_code=409, detail=str(exc))
    return {"status": "ok", "count": count}


@app.get("/health")
def health():
    return {"status": "ok"}
