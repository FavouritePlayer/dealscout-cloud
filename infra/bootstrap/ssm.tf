# SSM Parameter Store (standard tier, free) instead of Secrets Manager
# (which bills per secret). Values come from a gitignored terraform.tfvars
# — see terraform.tfvars.example. Variable declarations live in
# variables.tf.

locals {
  ssm_params = {
    "llm_provider"       = { value = var.llm_provider, secure = false }
    "anthropic_api_key"  = { value = var.anthropic_api_key, secure = true }
    "anthropic_model_id" = { value = var.anthropic_model_id, secure = false }
    "gemini_api_key"     = { value = var.gemini_api_key, secure = true }
    "gemini_model_id"    = { value = var.gemini_model_id, secure = false }
    "nebius_api_key"     = { value = var.nebius_api_key, secure = true }
    "nebius_model_id"    = { value = var.nebius_model_id, secure = false }
  }
}

resource "aws_ssm_parameter" "app" {
  for_each = local.ssm_params
  name     = "/${var.project_name}/${each.key}"
  type     = each.value.secure ? "SecureString" : "String"
  value    = each.value.value != "" ? each.value.value : "unset"
}
