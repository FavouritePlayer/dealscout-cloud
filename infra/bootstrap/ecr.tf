resource "aws_ecr_repository" "api" {
  name                 = "${var.project_name}/api"
  image_tag_mutability = "MUTABLE"
  force_delete         = true
}

resource "aws_ecr_repository" "scraper" {
  name                 = "${var.project_name}/scraper"
  image_tag_mutability = "MUTABLE"
  force_delete         = true
}

resource "aws_ecr_repository" "frontend" {
  name                 = "${var.project_name}/frontend"
  image_tag_mutability = "MUTABLE"
  force_delete         = true
}

# Mirror of the official qdrant/qdrant image so the cluster only ever
# depends on ECR, not Docker Hub's anonymous pull rate limits.
resource "aws_ecr_repository" "qdrant" {
  name                 = "${var.project_name}/qdrant"
  image_tag_mutability = "MUTABLE"
  force_delete         = true
}

# Keep each repo small — well within the 500MB-month free tier for a new
# account regardless, but this avoids accumulating old tags across
# up/destroy cycles.
resource "aws_ecr_lifecycle_policy" "expire_untagged" {
  for_each = {
    api      = aws_ecr_repository.api.name
    scraper  = aws_ecr_repository.scraper.name
    qdrant   = aws_ecr_repository.qdrant.name
    frontend = aws_ecr_repository.frontend.name
  }
  repository = each.value
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "expire untagged images after 7 days"
      selection = {
        tagStatus   = "untagged"
        countType   = "sinceImagePushed"
        countUnit   = "days"
        countNumber = 7
      }
      action = { type = "expire" }
    }]
  })
}
