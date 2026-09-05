#!/usr/bin/env bash
# Builds and pushes all three images to ECR. Also run automatically by CI
# on every push to main (see .github/workflows/build.yml) — run it
# locally for a first push, or to test a change before CI does.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BOOTSTRAP="$ROOT/infra/bootstrap"
PROFILE="${AWS_PROFILE:-dealscout}"
REGION="${AWS_REGION:-us-east-2}"

api_repo=$(terraform -chdir="$BOOTSTRAP" output -json ecr_repo_urls | jq -r .api)
scraper_repo=$(terraform -chdir="$BOOTSTRAP" output -json ecr_repo_urls | jq -r .scraper)
qdrant_repo=$(terraform -chdir="$BOOTSTRAP" output -json ecr_repo_urls | jq -r .qdrant)
registry="${api_repo%%/*}"

aws ecr get-login-password --profile "$PROFILE" --region "$REGION" | \
  docker login --username AWS --password-stdin "$registry"

echo "== api =="
docker build -f "$ROOT/backend/Dockerfile.api" -t "$api_repo:latest" "$ROOT"
docker push "$api_repo:latest"

echo "== scraper =="
docker build -f "$ROOT/backend/Dockerfile.scraper" -t "$scraper_repo:latest" "$ROOT"
docker push "$scraper_repo:latest"

echo "== qdrant (mirror of qdrant/qdrant, so the cluster never depends on Docker Hub) =="
docker pull qdrant/qdrant:latest
docker tag qdrant/qdrant:latest "$qdrant_repo:latest"
docker push "$qdrant_repo:latest"

echo "Done."
