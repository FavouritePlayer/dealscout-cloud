# Baseline (always-free) CloudWatch Logs tier: 5GB ingestion + 5GB storage
# per month. A short-lived demo cluster stays well under this.
resource "aws_cloudwatch_log_group" "app" {
  name              = "/${var.project_name}/app"
  retention_in_days = 7
}
