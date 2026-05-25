# ════════════════════════════════════════════════════════════════
# locals.tf — Tags estruturadas centralizadas
#
# Estratégia de tagging:
#   default_tags (provider) → tags globais em TODOS os recursos
#   tags por módulo          → Tier + Service (custo por camada)
#   tags por recurso         → Name (identificação individual)
# ════════════════════════════════════════════════════════════════

locals {
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

  # ── Tags usadas pelos módulos que aceitam tags via input ──────
  # VPC, ElastiCache, SQS e DynamoDB usam tags inline nos recursos;
  # estes locals estão disponíveis para passagem futura quando os
  # módulos forem refatorados para aceitar var.tags.
  tags_compute = merge(local.base_tags, { Tier = "compute", Service = "eks-kubernetes" })
  tags_data    = merge(local.base_tags, { Tier = "data", Service = "rds-postgresql" })
  tags_finops  = merge(local.base_tags, { Tier = "governance", Service = "finops-observability" })
}
