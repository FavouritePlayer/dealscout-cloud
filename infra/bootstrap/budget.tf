resource "aws_budgets_budget" "cost_guard" {
  name         = "${var.project_name}-cost-guard"
  budget_type  = "COST"
  limit_amount = tostring(var.budget_limit_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  # threshold=100 of type PERCENTAGE means "100% of the $8 limit" — i.e.
  # fire exactly when actual spend reaches $8, well under the $10 budget.
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.budget_alert_email]
  }
}
