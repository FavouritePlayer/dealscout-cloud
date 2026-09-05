#!/usr/bin/env bash
# Two-command lifecycle, part 1: stand up the EC2 instance + k3s +
# networking from scratch, wait for the node, then deploy the app.
#
#   ./scripts/up.sh      # bring the demo environment up
#   ./scripts/down.sh    # tear it all down, nothing left billing
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
INFRA="$ROOT/infra/ephemeral"
PROFILE="${AWS_PROFILE:-dealscout}"

if [ ! -f "$INFRA/terraform.tfvars" ]; then
  echo "Missing $INFRA/terraform.tfvars — copy terraform.tfvars.example and fill it in first." >&2
  exit 1
fi
if [ ! -d "$ROOT/infra/bootstrap/.terraform" ]; then
  echo "infra/bootstrap hasn't been applied yet — run ./scripts/bootstrap.sh once first." >&2
  exit 1
fi

echo "== terraform apply (infra/ephemeral) =="
terraform -chdir="$INFRA" init -upgrade=false
terraform -chdir="$INFRA" apply -auto-approve

echo "== waiting for k3s to report Ready (bootstrap log) =="
instance_id=$(terraform -chdir="$INFRA" output -raw instance_id)
for _ in $(seq 1 60); do
  status=$(aws ssm send-command --profile "$PROFILE" \
    --instance-ids "$instance_id" \
    --document-name "AWS-RunShellScript" \
    --parameters 'commands=["cat /var/log/dealscout/bootstrap.log 2>/dev/null || true"]' \
    --query "Command.CommandId" --output text 2>/dev/null) || { sleep 10; continue; }
  sleep 3
  out=$(aws ssm get-command-invocation --profile "$PROFILE" \
    --command-id "$status" --instance-id "$instance_id" \
    --query "StandardOutputContent" --output text 2>/dev/null) || true
  if [[ "$out" == *"k3s ready"* ]]; then
    echo "k3s is ready."
    break
  fi
  echo "  ...still waiting on the node (SSM agent needs a minute to come up first)"
  sleep 10
done

echo "== deploying app =="
"$ROOT/scripts/deploy.sh"

echo ""
echo "Up. Run ./scripts/down.sh when you're done to stop billing."
