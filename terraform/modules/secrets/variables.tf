variable "project_name" {
  description = "Nome do projeto"
  type        = string
}

variable "environment" {
  description = "Ambiente (prod | staging | dev)"
  type        = string
}

variable "aws_region" {
  description = "Região AWS"
  type        = string
}

# ── RDS ───────────────────────────────────────────────────────
variable "rds_username" {
  description = "Usuário administrador do PostgreSQL"
  type        = string
}

variable "rds_password" {
  description = "Senha do PostgreSQL"
  type        = string
  sensitive   = true
}

variable "rds_endpoints" {
  description = "Endpoints RDS por serviço (chave = nome do serviço)"
  type        = map(string)
}

variable "rds_ports" {
  description = "Portas RDS por serviço"
  type        = map(number)
}

variable "rds_db_names" {
  description = "Nome do banco de dados por serviço"
  type        = map(string)
}

# ── SQS ───────────────────────────────────────────────────────
variable "sqs_queue_url" {
  description = "URL da fila SQS (donation-service)"
  type        = string
}

# ── DynamoDB ──────────────────────────────────────────────────
variable "dynamodb_table_name" {
  description = "Nome da tabela DynamoDB (volunteer-service)"
  type        = string
}

# ── Tags ──────────────────────────────────────────────────────
variable "tags" {
  description = "Tags a aplicar nos recursos"
  type        = map(string)
  default     = {}
}
