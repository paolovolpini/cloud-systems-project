# le repo ECR ospitano le immagini che verranno:
# - pushate dal workflow per le app
# - pullate dalle istanze ec2

# mutable permette di poter prendere sempre la latest image

resource "aws_ecr_repository" "frontend" {
  name                 = "shortener-frontend"
  image_tag_mutability = "MUTABLE"
  image_scanning_configuration { scan_on_push = true }
  tags = { Name = "${var.cluster_name}-frontend" }
}

resource "aws_ecr_repository" "backend" {
  name                 = "shortener-backend"
  image_tag_mutability = "MUTABLE"
  image_scanning_configuration { scan_on_push = true }
  tags = { Name = "${var.cluster_name}-backend" }
}

# blocca più di 10 immagini nel repo

resource "aws_ecr_lifecycle_policy" "frontend" {
  repository = aws_ecr_repository.frontend.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Mantieni solo 10 immagini"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = { type = "expire" }
    }]
  })
}

resource "aws_ecr_lifecycle_policy" "backend" {
  repository = aws_ecr_repository.backend.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Mantieni solo 10 immagini"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = { type = "expire" }
    }]
  })
}