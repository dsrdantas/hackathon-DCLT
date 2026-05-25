# ════════════════════════════════════════════════════════════════
# locals.tf — Tags estruturadas centralizadas
#
# Estratégia de tagging:
#   default_tags (provider) → tags globais em TODOS os recursos
#   tags por módulo          → Tier + Service (custo por camada)
#   tags por recurso         → Name (identificação individual)
# ════════════════════════════════════════════════════════════════

locals {
  name_prefix = "${var.project_name}-${var.environment}"

  # ── Tags base (replicadas por camada de serviço) ─────────────
  base_tags = {
    Project     = var.project_name
    Environment = var.environment
    CostCenter  = var.cost_center
    Team        = var.team
    Owner       = var.owner_email
    Repository  = var.repository
    ManagedBy   = "Terraform"
  }

  # ── Tags por camada de infraestrutura ─────────────────────────
  tags_network    = merge(local.base_tags, { Tier = "network",   Service = "vpc-networking" })
  tags_compute    = merge(local.base_tags, { Tier = "compute",   Service = "eks-kubernetes" })
  tags_data       = merge(local.base_tags, { Tier = "data",      Service = "rds-postgresql" })
  tags_cache      = merge(local.base_tags, { Tier = "cache",     Service = "elasticache-redis" })
  tags_messaging  = merge(local.base_tags, { Tier = "messaging", Service = "sqs-donations" })
  tags_nosql      = merge(local.base_tags, { Tier = "data",      Service = "dynamodb-volunteers" })
  tags_finops     = merge(local.base_tags, { Tier = "governance", Service = "finops-observability" })
}
