# Architecture

What runs where, and why each infra decision was made — written to be defensible in an interview, not just functional.

## What runs where

| Component | Runs as | Where |
|---|---|---|
| Agent API (FastAPI + LangGraph) | k8s Deployment + Service (NodePort) | k3s on the EC2 node |
| Scraper (Playwright/Chromium + LLM valuation) | k8s Deployment + Service, auto-scrapes every 30 min and on demand via `POST /scrape` | k3s on the EC2 node |
| Qdrant (vector memory) | k8s Deployment + Service, backed by a PVC | k3s on the EC2 node |
| Listings cache | JSON file on a shared PVC | k3s on the EC2 node |
| Frontend (Next.js) | Not deployed to the cluster — run locally against the cloud API's NodePort during a demo | Your laptop |
| CI (build + push images) | GitHub Actions | GitHub |
| Everything else (ECR, SSM, CloudWatch, Budget) | AWS-managed | `us-east-2` |

The frontend isn't in the cluster because nothing in the graded surface area (containers, orchestration, ephemeral lifecycle) needs it there — running it locally against the NodePort keeps k8s scope and node resource pressure down without losing the demo.

## CI/CD auth: OIDC was the plan, a scoped IAM user is the reality

The original design authenticated GitHub Actions to AWS via OIDC — no long-lived keys stored anywhere. In practice, this AWS account (the "new AWS experience" tier) has an org-managed Service Control Policy that **explicitly denies all IAM OIDC-provider operations**, both `CreateOpenIDConnectProvider` and even `ListOpenIDConnectProviders` — confirmed by hitting an `AccessDenied` with an explicit-deny SCP citation on both calls. There's no way to route around this from Terraform or the CLI; the only way to unblock it is "activating advanced features" in AWS Settings, which converts the account into a full AWS Organizations management account — an irreversible, account-wide governance change (and one that deletes the account's existing spend limit) that is wildly disproportionate to unblocking one CI workflow's auth method.

So CI/CD here uses the real-world fallback: an IAM user (`infra/bootstrap/github_ci_user.tf`) whose policy is scoped to *only* `ecr:PutImage`-family actions on these 3 specific repos — no EC2, no IAM, no billing, nothing else — with its static access key stored as an encrypted GitHub Actions secret. This is a genuine, worth-naming-in-an-interview deviation from "no stored credentials": it's a standing credential, not OIDC's short-lived token exchange, but its blast radius if leaked is "someone can push images to 3 ECR repos," not "someone has broad account access." **Production fix**: run this in an AWS account without that SCP (a normal AWS Organizations member account created via IAM Identity Center, not this lightweight project tier), where OIDC federation works as originally designed.

## Why k3s-on-EC2 instead of EKS

EKS's control plane costs ~$73/month with **no free-tier coverage**, before a single worker node is added — that alone blows a $10 total budget. k3s is a real, CNCF-conformant Kubernetes distribution; running it single-node on a $0.02/hr EC2 instance gets Deployments, Services, and PVCs — the actual orchestration primitives being demonstrated — without paying for a managed control plane this project doesn't need. The tradeoff is real: no managed control-plane HA, no multi-AZ, no managed upgrades. That tradeoff is the right one for a single-node demo cluster that's up for a few hours at a time; it would not be the right one for production (see below).

## Why the cluster is ephemeral

A t3.small running 24/7 for a month costs ~$15 — a t3.micro ~$7.50 — either can consume most or all of a $10 total budget on compute alone, before EBS or data transfer. The fix isn't a smaller instance, it's not running continuously: `terraform apply`/`destroy` around each session keeps a multi-hour demo under $0.10, because you only pay for the hours the node actually exists. This is also why the Terraform is split into two layers:

- **`infra/bootstrap`** — ECR repos, SSM parameters, the CloudWatch log group, the GitHub OIDC role, the budget alert. All free or effectively free at rest (ECR storage is a few MB; SSM standard-tier and CloudWatch's baseline tier cost nothing at this volume). Applied once.
- **`infra/ephemeral`** — the VPC, subnet, security group, and the EC2 instance itself. This is what `up.sh`/`down.sh` cycle every session.

Splitting them means `terraform destroy` genuinely leaves nothing billing, without also deleting ECR images and having to rebuild them every session.

### No NAT Gateway, no Elastic IP, no open SSH

- A NAT Gateway is ~$32/month by itself — for a single node that only needs outbound internet (to pull images, hit the LLM API, scrape Craigslist), a public subnet with the node's own auto-assigned public IP does the same job for $0.
- No Elastic IP is allocated — an EIP not attached to a running instance bills hourly; the node's default public IP (which changes on every `up.sh`, that's fine for a session-scoped demo) avoids that entirely.
- The security group has **no inbound SSH**. Administration (fetching bootstrap status, running `kubectl`, creating secrets) goes through **SSM Session Manager / Run Command**, authenticated via the instance's IAM role — not a keypair over port 22. The only inbound rule is the demo NodePort (30080), scoped to your own IP (`/32`), not `0.0.0.0/0`.

### Cost

Per demo session (node up for ~2-3 hours, then destroyed):

| Item | Cost |
|---|---|
| EC2 t3.small, ~3 hrs | ~$0.06 |
| EBS gp3 20GB, prorated | a few cents |
| ECR, SSM, CloudWatch (baseline tiers) | $0 |
| NAT Gateway / Elastic IP | $0 (not used) |
| **Total per session** | **well under $0.10** |

Even 20-30 interview sessions in a month stays under $2-3, against a $10 budget with an $8 alert as backstop — the alert should never actually fire under normal use.

## Why a small always-on scraper service, not a CronJob

The original hackathon build scraped Craigslist synchronously, inside the FastAPI request handler, on every `/api/scan` call. That doesn't survive being split into separate containers (Step 3 asks for the agent/API and the Playwright scraper as distinct images), and it also means every scan pays full scrape latency.

The first cut of this redesign used a **CronJob** on a 30-minute schedule instead, writing scraped-and-valued listings (now including images for *every* listing, not just the final filtered queue — see `backend/scraper_job.py`; this was previously skipped as a perf optimization for the synchronous request path, which no longer applies once scraping isn't blocking a user request) to a JSON file on a shared PVC, with `/api/scan` reading that cache instead of scraping live. That got the API image off Chromium entirely, but it also meant the only way to force a fresh scrape was a human running `kubectl create job --from=cronjob/...` from the CLI — there was no way for the webapp itself to ask for one.

So the scraper is instead a small **Deployment** (`k8s/scraper.yaml`) exposing `POST /scrape` over the cluster network, plus a background thread that still re-scrapes on the same 30-minute interval so the cache doesn't go stale if nobody clicks anything. `/api/scan` calls that endpoint synchronously when the request sets `fresh: true` (the webapp's "Scrape now" button) before reading the cache — otherwise it reads the cache straight away, same as before. The API image still ships with no Chromium and no Playwright dependency; only the scraper container has that. The "idle capacity" concern that motivated the CronJob in the first place doesn't really apply here — this is a single EC2 node already running the API pod and Qdrant continuously, so one more small FastAPI process idling alongside them costs no extra money, it only costs some RAM headroom on the node, and Playwright's Chromium is only launched for the duration of an actual scrape, not held open between requests.

## Why Qdrant over pgvector

The hackathon build's memory layer (HydraDB, a sponsor SDK) had a narrow actual surface: ingest short preference strings scoped to `(tenant_id, user_id)`, semantic-search them back as free text, delete by id. Replacing it:

- Qdrant self-hosts as a single official image (`qdrant/qdrant`) with no schema or migrations to manage.
- Its native payload filtering maps directly onto HydraDB's `sub_tenant_id` partitioning — filter by a `user_id` field, same model.
- Upsert/search are synchronous, which is actually *simpler* than what it replaces — HydraDB required an ingest-then-poll-until-indexed loop (`_wait_for_indexing` in the old client) that Qdrant has no equivalent of.
- `langchain-qdrant` exists as a first-party LangGraph-friendly client if the integration ever needs to grow.

pgvector would need everything Qdrant needs (an embedding step — HydraDB did embedding internally, so this replacement uses a local `fastembed` model, no new API key) *plus* a full Postgres instance, SQL schema, and migrations on top. That's strictly more moving parts for the same actual requirement.

## No HPA — and why

Horizontal Pod Autoscaling has nothing to scale onto here: this is a single-node cluster with one API replica. HPA would create new pod replicas that all get scheduled onto the same single node, competing for the same fixed CPU/RAM rather than getting additional capacity — it's not meaningful without more nodes to spread onto. **Next step for production**: a managed multi-node cluster (EKS, or k3s across multiple nodes with a cluster autoscaler) where HPA has real capacity to scale into.

## What changes for real production use

| Demo choice | Production choice | Why |
|---|---|---|
| k3s on a single EC2 instance | Managed EKS (or GKE/AKS) | Managed control plane HA, multi-AZ, managed upgrades — worth the ~$73/month once uptime/reliability actually matters |
| Ephemeral (up/down per session) | Always-on | A real product needs to be reachable continuously, not just during a demo window |
| SSM Parameter Store | Secrets Manager | Automatic rotation and finer-grained access policies become worth the per-secret cost at production scale |
| No HPA | HPA (+ Cluster Autoscaler) | Real, variable traffic needs real elastic capacity across multiple nodes |
| NodePort + your own IP in the SG | ALB/NLB + proper TLS + WAF | A NodePort scoped to one operator's IP is a demo shortcut, not a public-facing entry point |
| Fixed 30-min auto-scrape + on-demand trigger | Event-driven or continuously-tuned scan cadence, likely with a real message queue between scraping and scoring | A demo's fixed schedule doesn't reflect real marketplace update patterns or scaling needs |
| Single Qdrant replica, PVC on local-path storage | Qdrant cluster mode (or a managed vector DB), replicated storage | A single-node PVC has no redundancy — fine for a disposable demo, not for data you can't afford to lose |
