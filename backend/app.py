import os
from pathlib import Path

from dotenv import load_dotenv

load_dotenv(Path(__file__).parent / ".env")

import httpx
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware

from backend.data.cache import read_listings_cache
from backend.graph.graph import feedback_graph, scan_graph
from backend.memory.qdrant_client import QdrantMemoryClient
from backend.memory.preference_parser import parse_preferences, preference_to_text
from backend.memory.schema import (
    FeedbackRequest,
    FeedbackResponse,
    PreferencesResponse,
    ScanRequest,
    ScanResponse,
    SetPreferencesRequest,
)

app = FastAPI()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

_memory = QdrantMemoryClient()

SCRAPER_URL = os.environ.get("SCRAPER_URL", "http://dealscout-scraper:8001")


def _trigger_live_scrape() -> None:
    """Ask the scraper service to refresh the listings cache and block
    until it's done (a real scrape takes well under the timeout below,
    including the LLM value-estimation and per-listing image fetch).

    A 409 means a scrape (scheduled or another on-demand trigger) is
    already in flight — treated as fine, since the cache is either about
    to be fresh or already is.
    """
    try:
        res = httpx.post(f"{SCRAPER_URL}/scrape", timeout=180.0)
    except httpx.HTTPError as exc:
        raise HTTPException(
            status_code=502,
            detail=f"Live scrape unavailable — couldn't reach the scraper service: {exc}",
        )
    if res.status_code not in (200, 409):
        raise HTTPException(
            status_code=502,
            detail=f"Live scrape failed (scraper returned {res.status_code}): {res.text}",
        )


@app.post("/api/scan", response_model=ScanResponse)
def scan(req: ScanRequest):
    if req.fresh:
        _trigger_live_scrape()
    candidates = read_listings_cache()
    if req.radius_miles is not None:
        candidates = [c for c in candidates if c["distance_miles"] <= req.radius_miles]
    result = scan_graph.invoke({
        "user_id": req.user_id,
        "radius_miles": req.radius_miles,
        "candidates": candidates,
    })
    return {
        "queue": result["queue"],
        "explanation": result["explanation"],
        "memory_used": parse_preferences(result["memory_context"]),
    }


@app.post("/api/feedback", response_model=FeedbackResponse)
def feedback(req: FeedbackRequest):
    if req.decision == "reject" and req.note:
        feedback_graph.invoke({"user_id": req.user_id, "feedback": req.note})
    added = parse_preferences(req.note) if req.decision == "reject" else []
    return {"ok": True, "preference_added": added[0] if added else None}


@app.get("/api/preferences/{user_id}", response_model=PreferencesResponse)
def preferences(user_id: str):
    text = _memory.recall(user_id=user_id, query="flip category and condition avoid-rules")
    return {"preferences": parse_preferences(text)}


@app.put("/api/preferences/{user_id}", response_model=PreferencesResponse)
def set_preferences(user_id: str, req: SetPreferencesRequest):
    texts = [preference_to_text(p.model_dump()) for p in req.preferences]
    _memory.replace_preferences(user_id, texts)
    return {"preferences": [p.model_dump() for p in req.preferences]}


@app.delete("/api/preferences/{user_id}")
def clear_preferences(user_id: str):
    _memory.forget_all(user_id)
    return {"ok": True}
