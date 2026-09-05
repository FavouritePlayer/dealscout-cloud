# Amazon Linux 2023 — ships with a modern kernel and the AWS CLI v2
# preinstalled, which the deploy script relies on for SSM/ECR calls.
data "aws_ssm_parameter" "al2023_ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

resource "aws_instance" "node" {
  ami                    = data.aws_ssm_parameter.al2023_ami.value
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.node.id]
  # References ../bootstrap's instance profile by its deterministic name
  # (see variables.tf note on project_name) rather than a cross-state
  # lookup — bootstrap must be applied first.
  iam_instance_profile = "${var.project_name}-node-profile"

  # No SSH key pair — administration goes through SSM Session Manager /
  # Run Command using the instance's IAM role, not a keypair over port 22.

  root_block_device {
    volume_size = var.root_volume_gb
    volume_type = "gp3"
  }

  user_data = templatefile("${path.module}/user_data.sh.tpl", {
    log_group_name = "/${var.project_name}/app"
  })
  # Changing user_data replaces the instance — fine for this ephemeral
  # pattern (every `apply` is meant to build fresh anyway).
  user_data_replace_on_change = true

  tags = { Name = "${var.project_name}-node" }
}
