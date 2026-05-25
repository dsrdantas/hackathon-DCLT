variable "project_name"   { type = string }
variable "environment"    { type = string }
variable "aws_region"     { type = string }
variable "alert_email"    { type = string; description = "E-mail para receber alertas de custo" }
variable "tags"           { type = map(string); default = {} }

# ── Budgets ───────────────────────────────────────────────────
variable "budget_monthly_total" {
  description = "Limite mensal total do projeto em USD"
  type        = number
}

variable "budget_eks" {
  description = "Limite mensal para camada compute (EKS) em USD"
  type        = number
}

variable "budget_data" {
  description = "Limite mensal para camada data (RDS + ElastiCache) em USD"
  type        = number
}

variable "budget_messaging" {
  description = "Limite mensal para camada messaging (SQS + DynamoDB) em USD"
  type        = number
}

variable "budget_alert_thresholds" {
  description = "Percentuais de alerta do budget (ex: [80, 100])"
  type        = list(number)
  default     = [80, 100]
}

# ── Anomaly Detection ─────────────────────────────────────────
variable "anomaly_threshold_usd" {
  description = "Valor mínimo em USD para disparar alerta de anomalia de custo"
  type        = number
}
