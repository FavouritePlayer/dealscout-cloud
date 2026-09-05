# k8s manifests

Applied by `scripts/deploy.sh`, which:
1. Substitutes `${ECR_API_IMAGE}` / `${ECR_SCRAPER_IMAGE}` / `${ECR_QDRANT_IMAGE}` with the actual ECR repo URLs from Terraform output.
2. Creates the `ecr-pull-secret` (a short-lived ECR auth token) and `dealscout-secrets` (pulled from SSM Parameter Store) — neither is committed as YAML.
3. Applies these manifests in order: `qdrant.yaml`, `listings-cache-pvc.yaml`, `api.yaml`, `scraper-cronjob.yaml`.

No HPA here on purpose — see ARCHITECTURE.md for why (single-node cluster, no second node for it to schedule onto).
