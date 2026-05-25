locals {
  name_prefix = "${var.project_name}-${var.environment}"
  # Extrai a versão major.minor para o parameter group (ex: "7.1" → "redis7")
  redis_family = "redis${split(".", var.engine_version)[0]}"
}

# ── Security Group ─────────────────────────────────────────────
resource "aws_security_group" "elasticache" {
  name        = "${local.name_prefix}-elasticache-sg"
  description = "ElastiCache Redis — acesso restrito aos nós EKS"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [var.eks_sg_id]
    description     = "Redis from EKS nodes"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound"
  }

  tags = { Name = "${local.name_prefix}-elasticache-sg" }
}

# ── Subnet Group (mínimo 2 AZs — requisito AWS) ───────────────
resource "aws_elasticache_subnet_group" "this" {
  name       = "${local.name_prefix}-elasticache-subnet-group"
  subnet_ids = var.subnet_ids
  tags       = { Name = "${local.name_prefix}-elasticache-subnet-group" }
}

# ── Parameter Group ───────────────────────────────────────────
resource "aws_elasticache_parameter_group" "this" {
  name   = "${local.name_prefix}-redis-params"
  family = local.redis_family
  tags   = { Name = "${local.name_prefix}-redis-params" }
}

# ── Redis Replication Group ───────────────────────────────────
resource "aws_elasticache_replication_group" "this" {
  replication_group_id = "${local.name_prefix}-redis"
  description          = "Redis para ${var.project_name} (${var.environment})"

  node_type            = var.node_type
  engine_version       = var.engine_version
  parameter_group_name = aws_elasticache_parameter_group.this.name
  port                 = 6379

  num_cache_clusters = var.num_cache_nodes

  subnet_group_name  = aws_elasticache_subnet_group.this.name
  security_group_ids = [aws_security_group.elasticache.id]

  at_rest_encryption_enabled = true
  transit_encryption_enabled = false # true requer AUTH token; habilitar em produção

  automatic_failover_enabled = var.num_cache_nodes > 1 ? true : false
  multi_az_enabled           = var.num_cache_nodes > 1 ? true : false

  snapshot_retention_limit = 1
  snapshot_window          = "03:00-04:00"
  maintenance_window       = "mon:04:00-mon:05:00"

  tags = { Name = "${local.name_prefix}-redis", Tier = "cache", Service = "elasticache-redis" }
}
