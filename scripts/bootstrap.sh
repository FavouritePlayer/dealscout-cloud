#!/usr/bin/env bash
# Run ONCE (or whenever you change LLM keys / the budget alert email) —
# not part of the per-session up/down cycle. Creates ECR repos, SSM
# parameters, the CloudWatch log group, the IAM role, and the Budget
# alert. All free or effectively free at rest, so there's no reason to
# tear these down between demo sessions.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BOOTSTRAP="$ROOT/infra/bootstrap"
source "$ROOT/scripts/lib/aws_creds.sh"

if [ ! -f "$BOOTSTRAP/terraform.tfvars" ]; then
  echo "Missing $BOOTSTRAP/terraform.tfvars — copy terraform.tfvars.example and fill it in first." >&2
  exit 1
fi

terraform -chdir="$BOOTSTRAP" init -upgrade=false
terraform -chdir="$BOOTSTRAP" apply -auto-approve

echo ""
echo "Bootstrap complete. Now mirror qdrant/qdrant and push your first images:"
echo "  ./scripts/build_and_push.sh"
echo "Then bring the demo environment up with ./scripts/up.sh"
