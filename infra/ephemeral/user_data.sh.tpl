#!/bin/bash
set -euxo pipefail

# CloudWatch agent for basic log shipping (baseline free tier).
dnf install -y amazon-cloudwatch-agent

cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json <<'EOF'
{
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/dealscout/*.log",
            "log_group_name": "${log_group_name}",
            "log_stream_name": "{instance_id}/{file_name}"
          }
        ]
      }
    }
  }
}
EOF
mkdir -p /var/log/dealscout
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config -m ec2 -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json -s

# k3s: single-node server. Traefik/servicelb/metrics-server are disabled —
# we expose the API via a plain NodePort Service and don't run anything
# that needs a LoadBalancer, so there's no reason to spend this node's
# limited RAM on an ingress controller we don't use.
curl -sfL https://get.k3s.io | \
  INSTALL_K3S_EXEC="server --disable traefik --disable servicelb --disable metrics-server --write-kubeconfig-mode 644" \
  sh -

# Wait for the node to be Ready before anything else touches kubectl.
until /usr/local/bin/k3s kubectl get nodes 2>/dev/null | grep -q " Ready"; do
  sleep 5
done

echo "k3s ready" > /var/log/dealscout/bootstrap.log
