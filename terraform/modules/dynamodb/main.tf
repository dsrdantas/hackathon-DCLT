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
# Nota: aws_iam_role_policy omitido — AWS Academy LabRole ja possui
# acesso a DynamoDB e nao permite iam:PutRolePolicy em roles externos.
