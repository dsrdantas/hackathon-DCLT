# ════════════════════════════════════════════════════════════════
# modules/secrets/main.tf
#
# Cria os secrets no AWS Secrets Manager com os valores extraídos
# dos outputs do Terraform (endpoints RDS, URL SQS, etc.).
#
# Autenticação do ESO: secretRef (credenciais estáticas AWS Academy)
# O K8s Secret "aws-academy-credentials" é criado pelo workflow
# .github/workflows/update-aws-credentials.yml — não pelo Terraform,
# pois as credenciais expiram a cada ~4h e precisam ser atualizadas
# sem re-executar o Terraform.
# ════════════════════════════════════════════════════════════════

locals {
  secret_path = "${var.project_name}/${var.environment}"
}

# ════════════════════════════════════════════════════════════════
# Secrets Manager — ngo-service
# Contém: database-url (PostgreSQL)
# ════════════════════════════════════════════════════════════════
resource "aws_secretsmanager_secret" "ngo_service" {
  name                    = "${local.secret_path}/ngo-service"
  description             = "Credenciais do ngo-service — populado pelo Terraform"
  recovery_window_in_days = 0

  tags = merge(var.tags, {
    Name    = "${local.secret_path}/ngo-service"
    Service = "ngo-service"
  })
}

resource "aws_secretsmanager_secret_version" "ngo_service" {
  secret_id = aws_secretsmanager_secret.ngo_service.id

  secret_string = jsonencode({
    "database-url" = "postgresql://${var.rds_username}:${var.rds_password}@${var.rds_endpoints["ngo"]}:${tostring(var.rds_ports["ngo"])}/${var.rds_db_names["ngo"]}"
  })
}

# ════════════════════════════════════════════════════════════════
# Secrets Manager — donation-service
# Contém: database-url (PostgreSQL) + sqs-queue-url
# ════════════════════════════════════════════════════════════════
resource "aws_secretsmanager_secret" "donation_service" {
  name                    = "${local.secret_path}/donation-service"
  description             = "Credenciais do donation-service — populado pelo Terraform"
  recovery_window_in_days = 0

  tags = merge(var.tags, {
    Name    = "${local.secret_path}/donation-service"
    Service = "donation-service"
  })
}

resource "aws_secretsmanager_secret_version" "donation_service" {
  secret_id = aws_secretsmanager_secret.donation_service.id

  secret_string = jsonencode({
    "database-url"  = "postgresql://${var.rds_username}:${var.rds_password}@${var.rds_endpoints["donation"]}:${tostring(var.rds_ports["donation"])}/${var.rds_db_names["donation"]}"
    "sqs-queue-url" = var.sqs_queue_url
  })
}

# ════════════════════════════════════════════════════════════════
# Secrets Manager — volunteer-service
# Contém: dynamodb-table + aws-region
# ════════════════════════════════════════════════════════════════
resource "aws_secretsmanager_secret" "volunteer_service" {
  name                    = "${local.secret_path}/volunteer-service"
  description             = "Configuração do volunteer-service — populado pelo Terraform"
  recovery_window_in_days = 0

  tags = merge(var.tags, {
    Name    = "${local.secret_path}/volunteer-service"
    Service = "volunteer-service"
  })
}

resource "aws_secretsmanager_secret_version" "volunteer_service" {
  secret_id = aws_secretsmanager_secret.volunteer_service.id

  secret_string = jsonencode({
    "dynamodb-table" = var.dynamodb_table_name
    "aws-region"     = var.aws_region
  })
}
