variable "aws_region" {
  description = "AWS region. Locked to the new-experience project's assigned region."
  type        = string
  default     = "us-east-2"
}

variable "aws_profile" {
  type    = string
  default = "dealscout"
}

variable "project_name" {
  description = "Must match ../bootstrap's project_name — the IAM instance profile and CloudWatch log group are referenced by their deterministic names, not cross-state lookups."
  type        = string
  default     = "dealscout"
}

variable "instance_type" {
  description = "t3.small by default: k3s + Qdrant + the API + an occasional Chromium scrape job is tight on t3.micro's 1GB RAM. t3.micro still works if you want to shave the (already tiny) hourly cost further."
  type        = string
  default     = "t3.small"
}

variable "my_ip" {
  description = "Your current public IP (no CIDR suffix), used to scope the security group instead of opening the demo port to 0.0.0.0/0. Fetch it with `curl -s https://checkip.amazonaws.com`."
  type        = string
}

variable "root_volume_gb" {
  type    = number
  default = 20
}
