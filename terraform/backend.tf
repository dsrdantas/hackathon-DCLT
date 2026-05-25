terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.14"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.32"
    }
  }

  backend "s3" {
    bucket         = "solidarytech-prod-tfstate"
    key            = "infra/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "solidarytech-prod-terraform-lock"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region

  # ── Tags aplicadas automaticamente em TODOS os recursos AWS ──
  default_tags {
    tags = {
      # Identificação
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
      Repository  = var.repository

      # FinOps / Faturamento
      CostCenter = var.cost_center
      Team       = var.team
      Owner      = var.owner_email
    }
  }
}
