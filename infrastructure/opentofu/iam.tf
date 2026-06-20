# in modo simile a come la repo github si autentica con il ruolo
# anche le ec2 devono avere i ruoli per interagire con l'api AWS

# ogni role policy ha un effetto, un action e un Principal che definisce 
# chi è in grado di assumere il ruolo

resource "aws_iam_role" "control_plane" {
  name = "${var.cluster_name}-control-plane-role"
  # permette ad EC2 di assumere il ruolo
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

# il control plane deve avere permessi per scrivere su SSM

resource "aws_iam_role_policy" "control_plane_ssm" {
  name = "ssm-policy"
  role = aws_iam_role.control_plane.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "ssm:PutParameter",
        "ssm:GetParameter"
      ]
      Resource = "arn:aws:ssm:${var.aws_region}:*:parameter/${var.cluster_name}/*"
    }]
  })
}

resource "aws_iam_instance_profile" "control_plane" {
  name = "${var.cluster_name}-control-plane-profile"
  role = aws_iam_role.control_plane.name
}

# i worker devono solo pullare immagini e leggere SSM

resource "aws_iam_role" "workers" {
  name = "${var.cluster_name}-workers-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "workers_ssm_ecr" {
  name = "ssm-ecr-policy"
  role = aws_iam_role.workers.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ssm:GetParameter"]
        Resource = "arn:aws:ssm:${var.aws_region}:*:parameter/${var.cluster_name}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "workers" {
  name = "${var.cluster_name}-workers-profile"
  role = aws_iam_role.workers.name
}