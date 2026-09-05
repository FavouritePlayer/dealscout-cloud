# DealScout Cloud

A memory-powered resale arbitrage agent — LangGraph agent, Playwright scraper, Qdrant vector memory — containerized and deployed to a disposable k3s-on-EC2 cluster on AWS. Built as a container/orchestration demo: bring the environment up before an interview, tear it down after, nothing bills in between.

Forked from the [Agents You Love Hackathon](https://agentsyoulove.dev) build; this repo replaces the hackathon-sponsor memory backend with a self-hostable one and adds all the cloud infrastructure. See [ARCHITECTURE.md](ARCHITECTURE.md) for the full reasoning behind every infra decision.

## What it does

DealScout scans Craigslist listings across multiple categories (furniture, electronics, tools, collectibles, sporting goods, instruments), estimates resale value with an LLM, and ranks items by projected profit. You review a queue of flip candidates and reject anything you don't want to deal with — *"I don't flip furniture, too much hassle to move."* DealScout stores that preference in Qdrant and excludes matching items on every future scan without you re-stating yourself.

## Tech stack

| Layer | Technologies |
|---|---|
| Agent | LangGraph, Python |
| Memory | Qdrant (self-hosted vector store) + local `fastembed` embeddings |
| LLM | Anthropic / Gemini / Nebius (OpenAI-compatible) |
| Scraping | Playwright (headless Chromium), a small k8s Deployment: auto-scrapes every 30 min, plus on-demand via `POST /scrape` |
| Backend | FastAPI, Pydantic |
| Frontend | Next.js 15, React 19, Tailwind CSS 4, TypeScript |
| Infra | Terraform, k3s on a single EC2 instance, ECR, SSM Parameter Store, CloudWatch Logs |

## Architecture

```
Scraper (Deployment, Playwright/Chromium)  ──every 30 min, or on demand──▶  listings cache (PVC)
                                                                                    │
POST /api/scan {fresh: true}  ──▶  Agent API (Deployment)  ──POST /scrape──▶ Scraper
    ├─ read cache ◀─────────────────────────────────────────────────────────────────┘
    ├─ retrieve_memory  →  Qdrant (user avoid/prefer rules)
    ├─ classify_value   →  margin arithmetic (25% threshold)
    └─ filter_and_rank  →  LLM filters by memory, sorts by profit
    │
    ▼
Next.js UI (run locally against the cloud API) — queue cards, memory panel, saved flips, history
    │
    ▼
POST /api/feedback  →  update_memory  →  Qdrant upsert
```

## Local development

```bash
git clone https://github.com/FavouritePlayer/dealscout-cloud.git
cd dealscout-cloud
cp backend/.env.example backend/.env   # fill in an LLM key

docker compose up --build          # qdrant, api, frontend
docker compose --profile scraper run scraper   # seed the listings cache once
```

Open [http://localhost:3000](http://localhost:3000). Re-run the scraper profile whenever you want fresh listings; the API always reads whatever's in the cache.

### Tests

```bash
cd backend && python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt && pip install playwright && playwright install chromium
pytest tests/
```

## Cloud deployment — two-command lifecycle

**One-time setup** (persistent, cheap-to-free resources — ECR repos, SSM parameters, CloudWatch log group, the GitHub CI IAM user, the $8 budget alert):

```bash
cp infra/bootstrap/terraform.tfvars.example infra/bootstrap/terraform.tfvars   # fill in your LLM key + alert email
./scripts/bootstrap.sh
./scripts/build_and_push.sh   # first image push (CI handles it after this)
```

**Every demo session** — this is the two-command part:

```bash
cp infra/ephemeral/terraform.tfvars.example infra/ephemeral/terraform.tfvars   # your current IP changes between sessions
./scripts/up.sh      # EC2 + k3s + networking from scratch, then deploys the app
./scripts/down.sh    # tears the instance/SG/EBS volume down, nothing left billing
```

`up.sh` prints the API URL (`http://<node-ip>:30080`) when it's done. Point the local frontend at it:

```bash
cd frontend && BACKEND_URL=http://<node-ip>:30080 npm run dev
```

The scraper auto-refreshes the listings cache every 30 minutes on its own, and the webapp's **Scrape now** button triggers one immediately (it calls `POST /api/scan` with `fresh: true`, which the agent API forwards to the scraper's `POST /scrape`) — no need to shell into the node for a fresh scrape before a demo.

**Cost**: well under $0.10 per multi-hour demo session (see [ARCHITECTURE.md](ARCHITECTURE.md#cost)). The $8 budget alert is a backstop, not the expected spend.

## CI/CD

Every push to `main` builds and pushes all three images to ECR via GitHub Actions. Auth was originally designed as OIDC (no stored keys); this account's org SCPs block all OIDC-provider IAM operations, so it falls back to a scoped IAM user (ECR push only, nothing else) with its key as an encrypted GitHub secret — see [ARCHITECTURE.md](ARCHITECTURE.md#cicd-auth-oidc-was-the-plan-a-scoped-iam-user-is-the-reality) for why. CI does **not** auto-deploy — the cluster is ephemeral and often won't exist when CI runs. Deploy manually with `./scripts/deploy.sh` (or `up.sh`, which calls it) whenever the environment is up.

## API

| Method | Endpoint | Description |
|---|---|---|
| `POST` | `/api/scan` | Read cached listings, classify, filter by memory, return queue |
| `POST` | `/api/feedback` | Accept or reject an item (reject writes to Qdrant) |
| `GET` | `/api/preferences/:user_id` | List stored preferences |
| `PUT` | `/api/preferences/:user_id` | Replace all preferences |
| `DELETE` | `/api/preferences/:user_id` | Clear all memories for a user |

## Project structure

```
dealscout-cloud/
├── backend/
│   ├── app.py                    # FastAPI server (no Playwright dependency)
│   ├── scraper_job.py            # scraper service entrypoint (Playwright), FastAPI + auto-scrape thread
│   ├── graph/                    # LangGraph agent (scan + feedback pipelines)
│   ├── memory/                   # Qdrant client, preference parsing
│   └── data/                     # live_loader (scrape+value), cache (shared with API)
├── frontend/                     # Next.js UI
├── infra/
│   ├── bootstrap/                # one-time: ECR, SSM, CloudWatch, budget, GitHub CI IAM user
│   └── ephemeral/                # per-session: VPC, SG, EC2+k3s
├── k8s/                          # Deployment/Service for API, scraper, Qdrant
├── scripts/                      # bootstrap.sh, build_and_push.sh, up.sh, down.sh, deploy.sh
└── .github/workflows/build.yml   # CI: build+push on push to main, no auto-deploy
```

## License

MIT
