output "ecr_repo_urls" {
  value = {
    api     = aws_ecr_repository.api.repository_url
    scraper = aws_ecr_repository.scraper.repository_url
    qdrant  = aws_ecr_repository.qdrant.repository_url
  }
}

output "cloudwatch_log_group" {
  value = aws_cloudwatch_log_group.app.name
}

output "iam_instance_profile_name" {
  value = aws_iam_instance_profile.node.name
}
