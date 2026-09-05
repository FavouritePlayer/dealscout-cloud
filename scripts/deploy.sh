#!/usr/bin/env bash
# Pushes the manifests + fresh secrets to the running k3s node and applies
# them. Run this after `terraform apply` (up.sh does this for you).
#
# kubectl runs only on the node itself (via SSM Run Command) — the k3s API
# server (6443) is never exposed publicly, so there's nothing to reach it
# with remotely. This script ships each manifest to the node as a
# base64-encoded blob inside an SSM command, decodes it there, and applies.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
INFRA="$ROOT/infra/ephemeral"
BOOTSTRAP="$ROOT/infra/bootstrap"
PROFILE="${AWS_PROFILE:-dealscout}"
REGION="${AWS_REGION:-us-east-2}"

instance_id=$(terraform -chdir="$INFRA" output -raw instance_id)
api_image=$(terraform -chdir="$BOOTSTRAP" output -json ecr_repo_urls | jq -r .api):latest
scraper_image=$(terraform -chdir="$BOOTSTRAP" output -json ecr_repo_urls | jq -r .scraper):latest
qdrant_image=$(terraform -chdir="$BOOTSTRAP" output -json ecr_repo_urls | jq -r .qdrant):latest
project_name="dealscout"

run_remote() {
  # Sends $1 (a shell script) to the node via SSM Run Command and blocks
  # until it finishes, printing stdout/stderr.
  local script="$1"
  local cmd_id
  cmd_id=$(aws ssm send-command \
    --profile "$PROFILE" --region "$REGION" \
    --instance-ids "$instance_id" \
    --document-name "AWS-RunShellScript" \
    --parameters "commands=[$(jq -Rs . <<<"$script")]" \
    --query "Command.CommandId" --output text)

  aws ssm wait command-executed \
    --profile "$PROFILE" --region "$REGION" \
    --command-id "$cmd_id" --instance-id "$instance_id" 2>/dev/null || true

  aws ssm get-command-invocation \
    --profile "$PROFILE" --region "$REGION" \
    --command-id "$cmd_id" --instance-id "$instance_id" \
    --query "{status:Status,stdout:StandardOutputContent,stderr:StandardErrorContent}" \
    --output json
}

echo "== Refreshing ECR pull secret and app secrets on the node =="
ecr_password=$(aws ecr get-login-password --profile "$PROFILE" --region "$REGION")
account_id=$(aws sts get-caller-identity --profile "$PROFILE" --region "$REGION" --query Account --output text)

llm_provider=$(aws ssm get-parameter --profile "$PROFILE" --region "$REGION" --name "/${project_name}/llm_provider" --query Parameter.Value --output text)
anthropic_key=$(aws ssm get-parameter --profile "$PROFILE" --region "$REGION" --name "/${project_name}/anthropic_api_key" --with-decryption --query Parameter.Value --output text)
anthropic_model=$(aws ssm get-parameter --profile "$PROFILE" --region "$REGION" --name "/${project_name}/anthropic_model_id" --query Parameter.Value --output text)
gemini_key=$(aws ssm get-parameter --profile "$PROFILE" --region "$REGION" --name "/${project_name}/gemini_api_key" --with-decryption --query Parameter.Value --output text)
gemini_model=$(aws ssm get-parameter --profile "$PROFILE" --region "$REGION" --name "/${project_name}/gemini_model_id" --query Parameter.Value --output text)
nebius_key=$(aws ssm get-parameter --profile "$PROFILE" --region "$REGION" --name "/${project_name}/nebius_api_key" --with-decryption --query Parameter.Value --output text)
nebius_model=$(aws ssm get-parameter --profile "$PROFILE" --region "$REGION" --name "/${project_name}/nebius_model_id" --query Parameter.Value --output text)
openai_key=$(aws ssm get-parameter --profile "$PROFILE" --region "$REGION" --name "/${project_name}/openai_api_key" --with-decryption --query Parameter.Value --output text)
openai_model=$(aws ssm get-parameter --profile "$PROFILE" --region "$REGION" --name "/${project_name}/openai_model_id" --query Parameter.Value --output text)

secrets_script=$(cat <<EOF
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
kubectl delete secret ecr-pull-secret dealscout-secrets --ignore-not-found
kubectl create secret docker-registry ecr-pull-secret \
  --docker-server="${account_id}.dkr.ecr.${REGION}.amazonaws.com" \
  --docker-username=AWS --docker-password="${ecr_password}"
kubectl create secret generic dealscout-secrets \
  --from-literal=LLM_PROVIDER="${llm_provider}" \
  --from-literal=ANTHROPIC_API_KEY="${anthropic_key}" \
  --from-literal=ANTHROPIC_MODEL_ID="${anthropic_model}" \
  --from-literal=GEMINI_API_KEY="${gemini_key}" \
  --from-literal=GEMINI_MODEL_ID="${gemini_model}" \
  --from-literal=NEBIUS_API_KEY="${nebius_key}" \
  --from-literal=NEBIUS_MODEL_ID="${nebius_model}" \
  --from-literal=OPENAI_API_KEY="${openai_key}" \
  --from-literal=OPENAI_MODEL_ID="${openai_model}"
EOF
)
run_remote "$secrets_script"

echo "== Applying manifests =="
apply_manifest() {
  local file="$1"
  local b64
  b64=$(base64 < "$file" | tr -d '\n')
  local script="export KUBECONFIG=/etc/rancher/k3s/k3s.yaml; echo '$b64' | base64 -d > /tmp/$(basename "$file") && kubectl apply -f /tmp/$(basename "$file")"
  run_remote "$script"
}

for f in qdrant.yaml listings-cache-pvc.yaml api.yaml scraper-cronjob.yaml; do
  tmp=$(mktemp)
  sed -e "s#\${ECR_API_IMAGE}#${api_image}#g" \
      -e "s#\${ECR_SCRAPER_IMAGE}#${scraper_image}#g" \
      -e "s#\${ECR_QDRANT_IMAGE}#${qdrant_image}#g" \
      "$ROOT/k8s/$f" > "$tmp"
  echo "-- $f --"
  apply_manifest "$tmp"
  rm -f "$tmp"
done

api_url=$(terraform -chdir="$INFRA" output -raw api_url)
echo ""
echo "Deployed. API should be reachable at: $api_url"
echo "Trigger an immediate scrape (don't wait for the schedule):"
echo "  aws ssm send-command --profile $PROFILE --region $REGION --instance-ids $instance_id \\"
echo "    --document-name AWS-RunShellScript \\"
echo "    --parameters 'commands=[\"export KUBECONFIG=/etc/rancher/k3s/k3s.yaml; kubectl create job --from=cronjob/dealscout-scraper manual-scan-\$(date +%s)\"]'"
