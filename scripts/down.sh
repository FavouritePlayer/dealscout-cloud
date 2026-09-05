#!/usr/bin/env bash
# Two-command lifecycle, part 2: tear everything down (instance, security
# group, EBS volume, networking). ECR repos, SSM parameters, the
# CloudWatch log group, and the Budget alert are cheap-to-free at rest and
# are left in place so up.sh doesn't need to recreate them next time — see
# ARCHITECTURE.md if you want a true zero-resource teardown instead.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
INFRA="$ROOT/infra/ephemeral"
source "$ROOT/scripts/lib/aws_creds.sh"

terraform -chdir="$INFRA" destroy -auto-approve

echo "Down. Nothing billing except ECR storage (a few MB, well under the free tier)."
