# DealScout

A memory-powered resale arbitrage agent that scans live marketplace listings, surfaces undervalued flip opportunities, and learns from your feedback over time.

Built for the [Agents You Love Hackathon](https://agentsyoulove.dev) — theme: *Context over Amnesia*.

## What it does

DealScout scans Craigslist listings across multiple categories (furniture, electronics, tools, collectibles, sporting goods, instruments), estimates resale value with an LLM, and ranks items by projected profit. You review a queue of flip candidates and reject anything you don't want to deal with — *"I don't flip furniture, too much hassle to move."* DealScout stores that preference in [HydraDB](https://hydradb.ai) and excludes matching items on every future scan without you re-stating yourself.

**The memory is load-bearing:** remove it and the product breaks.

## Demo flow

1. **Scan** — Playwright scrapes live listings; the agent classifies each as undervalued or overvalued and returns a ranked queue.
2. **Reject with a reason** — Your rejection text is ingested into HydraDB as a long-term memory.
3. **Rescan** — The agent recalls your preferences autonomously and fully excludes matching categories from the queue, citing your original reason.

## Tech stack

| Layer | Technologies |
|---|---|
| Agent | LangGraph, Python |
| Memory | HydraDB (semantic memory + graph relations) |
| LLM | Anthropic / Gemini / Nebius (OpenAI-compatible) |
| Scraping | Playwright (headless Chromium) |
| Backend | FastAPI, Pydantic |
| Frontend | Next.js 15, React 19, Tailwind CSS 4, TypeScript |

## Architecture

```
POST /api/scan
    │
    ▼
LangGraph scan pipeline
    ├─ retrieve_memory  →  HydraDB (user avoid/prefer rules)
    ├─ classify_value   →  margin arithmetic (25% threshold)
    └─ filter_and_rank  →  LLM filters by memory, sorts by profit
    │
    ▼
Live Craigslist scrape (Playwright) + LLM valuation
    │
    ▼
Next.js UI — queue cards, memory panel, saved flips, history
    │
    ▼
POST /api/feedback  →  update_memory  →  HydraDB ingest
```

## Features

- **Live scraping** — Real titles and asking prices from Craigslist (SF Bay Area)
- **LLM valuation** — Estimates resale value, condition, and description from listing titles
- **Persistent memory** — Rejection reasons become durable avoid-rules via HydraDB
- **Editable preferences** — Add, edit, or remove rules in the Memory view; syncs back to HydraDB
- **Saved flips** — Bookmark promising listings for later
- **Action history** — Timeline of scans, rejections, saves, and memory edits

## Getting started

### Prerequisites

- Python 3.11+
- Node.js 20+
- API keys for HydraDB and an LLM provider (see `backend/.env.example`)

### Setup

```bash
# Clone and enter the repo
git clone https://github.com/FavouritePlayer/DealScout.git
cd DealScout

# Backend
python3 -m venv backend/.venv
source backend/.venv/bin/activate
pip install -r backend/requirements.txt
playwright install chromium
cp backend/.env.example backend/.env   # fill in your keys

# Frontend
cd frontend && npm install && cd ..
```

### Run

**Two terminals:**

```bash
# Terminal 1 — backend (from repo root)
source backend/.venv/bin/activate
python -m uvicorn backend.app:app --host 0.0.0.0 --port 8000

# Terminal 2 — frontend
cd frontend && npm run dev
```

Or use the helper script:

```bash
chmod +x scripts/dev.sh
./scripts/dev.sh
```

Open [http://localhost:3000](http://localhost:3000).

Set `PLAYWRIGHT_HEADED=1` to watch Chromium scrape live during scans.

## API

| Method | Endpoint | Description |
|---|---|---|
| `POST` | `/api/scan` | Scrape listings, classify, filter by memory, return queue |
| `POST` | `/api/feedback` | Accept or reject an item (reject writes to HydraDB) |
| `GET` | `/api/preferences/:user_id` | List stored preferences |
| `PUT` | `/api/preferences/:user_id` | Replace all preferences |
| `DELETE` | `/api/preferences/:user_id` | Clear all memories for a user |

## Project structure

```
DealScout/
├── backend/
│   ├── app.py                  # FastAPI server
│   ├── graph/                  # LangGraph agent (scan + feedback pipelines)
│   ├── memory/                 # HydraDB client, preference parsing
│   └── data/
│       ├── live_loader.py      # Live Craigslist scrape + LLM valuation
│       └── listings_fixture.json
├── frontend/
│   ├── app/                    # Next.js pages and components
│   └── lib/                    # API client, types, history store
└── scripts/
    └── dev.sh                  # Start both servers
```

## Tests

```bash
source backend/.venv/bin/activate
pytest backend/tests/
```

## License

MIT
