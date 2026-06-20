terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket = "s3-bucket-pablo-cloud-system"
    key    = "k8s/terraform.tfstate"
    region = "eu-south-1"
  }
}

provider "aws" {
  region = "eu-south-1"
}