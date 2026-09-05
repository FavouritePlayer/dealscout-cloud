variable "aws_region" {
  type    = string
  default = "us-east-2"
}

variable "aws_profile" {
  type    = string
  default = "dealscout"
}

variable "project_name" {
  type    = string
  default = "dealscout"
}

variable "budget_limit_usd" {
  type    = number
  default = 8
}

variable "budget_alert_email" {
  description = "Email address for the AWS Budget alert."
  type        = string
}

variable "llm_provider" {
  type    = string
  default = "anthropic"
}

variable "anthropic_api_key" {
  type      = string
  default   = ""
  sensitive = true
}

variable "anthropic_model_id" {
  type    = string
  default = "claude-haiku-4-5-20251001"
}

variable "gemini_api_key" {
  type      = string
  default   = ""
  sensitive = true
}

variable "gemini_model_id" {
  type    = string
  default = "gemini-2.5-flash"
}

variable "nebius_api_key" {
  type      = string
  default   = ""
  sensitive = true
}

variable "nebius_model_id" {
  type    = string
  default = ""
}
