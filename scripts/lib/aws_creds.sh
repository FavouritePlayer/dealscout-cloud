# Terraform's AWS provider doesn't understand the newer `aws login`
# browser-based session format that `aws configure agent-toolkit` sets up
# (it shows up in ~/.aws/config as `login_session`, not a credential
# source the Go AWS SDK recognizes yet). `aws` CLI commands work fine
# with --profile directly; Terraform needs plain exported credentials, so
# resolve them once here and export them for the terraform invocation.
eval "$(aws configure export-credentials --profile "${AWS_PROFILE:-dealscout}" --format env)"
