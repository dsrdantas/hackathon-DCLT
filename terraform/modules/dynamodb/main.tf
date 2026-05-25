locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

# ── Tabela DynamoDB ───────────────────────────────────────────
resource "aws_dynamodb_table" "volunteers" {
  name         = var.table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "volunteer_id"

  attribute {
    name = "volunteer_id"
    type = "S"
  }

  # GSI para buscar voluntários por ONG (equivale ao Scan atual + filtro)
  global_secondary_index {
    name            = "ngo_id-index"
    hash_key        = "ngo_id"
    projection_type = "ALL"
  }

  attribute {
    name = "ngo_id"
    type = "N"
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled = true
  }

  tags = { Name = var.table_name, Tier = "data", Service = "dynamodb-volunteers" }
}

# ── IAM Policy — nós EKS acessam a tabela ────────────────────
resource "aws_iam_role_policy" "dynamodb_access" {
  name = "${local.name_prefix}-dynamodb-volunteers"
  # Extrai o nome da role do ARN
  role = element(split("/", var.eks_node_role_arn), length(split("/", var.eks_node_role_arn)) - 1)

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:Scan",
          "dynamodb:Query"
        ]
        Resource = [
          aws_dynamodb_table.volunteers.arn,
          "${aws_dynamodb_table.volunteers.arn}/index/*"
        ]
      }
    ]
  })
}
