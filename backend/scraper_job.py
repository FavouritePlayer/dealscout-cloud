"""Entrypoint for the scraper image, run as a k8s CronJob (or a one-off Job
triggered manually before a demo: `kubectl create job --from=cronjob/...`).

Scrapes live listings, estimates resale value, and — unlike the old
request-path flow — fetches an image for every listing (not just the
post-filter queue) since this runs on a schedule rather than blocking a
user's request, so the per-listing page visit cost no longer matters.
Writes the result to the shared cache the agent API reads from.
"""
import logging

from backend.data.cache import write_listings_cache
from backend.data.live_loader import attach_images, load_listings

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def main() -> None:
    listings = load_listings()
    listings = attach_images(listings)
    write_listings_cache(listings)
    logger.info("wrote %d listings to cache", len(listings))


if __name__ == "__main__":
    main()
