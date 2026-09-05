# Fallback for CI/CD auth: this account's org-managed SCPs deny ALL IAM
# OIDC-provider operations (create AND list), so GitHub Actions can't
# federate via OIDC here — see ARCHITECTURE.md. A scoped IAM user with a
# static access key, stored as an encrypted GitHub Actions secret, is the
# real-world fallback: permissions are limited to pushing these 3 ECR
# repos only (no EC2, no IAM, no billing access), but it is a standing
# credential rather than OIDC's short-lived token exchange.

resource "aws_iam_user" "github_ci" {
  name = "${var.project_name}-github-ci"
}

resource "aws_iam_user_policy" "github_ci_ecr_push" {
  name = "${var.project_name}-github-ci-ecr-push"
  user = aws_iam_user.github_ci.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "ecr:GetAuthorizationToken"
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:BatchGetImage",
        ]
        Resource = [
          aws_ecr_repository.api.arn,
          aws_ecr_repository.scraper.arn,
          aws_ecr_repository.qdrant.arn,
        ]
      },
    ]
  })
}

resource "aws_iam_access_key" "github_ci" {
  user = aws_iam_user.github_ci.name
}

output "github_ci_access_key_id" {
  value = aws_iam_access_key.github_ci.id
}

output "github_ci_secret_access_key" {
  value     = aws_iam_access_key.github_ci.secret
  sensitive = true
}
