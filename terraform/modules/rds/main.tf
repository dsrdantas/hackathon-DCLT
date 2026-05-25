locals {
  # ex: solidarytech-prod-ngo | solidarytech-prod-donation
  name_prefix = "${var.project_name}-${var.environment}-${var.service_name}"
  service_tag = "rds-${var.service_name}"
}

# ════════════════════════════════════════════════════════════════
# Security Group — exclusivo por serviço
# Apenas o EKS node SG pode conectar na porta 5432
# ════════════════════════════════════════════════════════════════
resource "aws_security_group" "rds" {
  name        = "${local.name_prefix}-rds-sg"
  description = "RDS PostgreSQL ${var.service_name} — acesso restrito aos nós EKS"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [var.eks_sg_id]
    description     = "PostgreSQL from EKS nodes → ${var.service_name}-service"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound"
  }

  tags = {
    Name    = "${local.name_prefix}-rds-sg"
    Tier    = "data"
    Service = local.service_tag
  }
}

# ════════════════════════════════════════════════════════════════
# Subnet Group — subnets isoladas por serviço (mínimo 2 AZs)
# ════════════════════════════════════════════════════════════════
resource "aws_db_subnet_group" "this" {
  name        = "${local.name_prefix}-subnet-group"
  subnet_ids  = var.subnet_ids
  description = "Subnet group exclusivo para RDS ${var.service_name}"

  tags = {
    Name    = "${local.name_prefix}-subnet-group"
    Tier    = "data"
    Service = local.service_tag
  }
}

# ════════════════════════════════════════════════════════════════
# Parameter Group — tuning por serviço
# ════════════════════════════════════════════════════════════════
resource "aws_db_parameter_group" "this" {
  name        = "${local.name_prefix}-pg16"
  family      = "postgres16"
  description = "PostgreSQL 16 — ${var.service_name}-service"

  parameter {
    name  = "log_connections"
    value = "1"
  }

  parameter {
    name  = "log_disconnections"
    value = "1"
  }

  tags = {
    Name    = "${local.name_prefix}-pg16"
    Tier    = "data"
    Service = local.service_tag
  }
}

# ════════════════════════════════════════════════════════════════
# RDS Instance
# ════════════════════════════════════════════════════════════════
resource "aws_db_instance" "this" {
  identifier = "${local.name_prefix}-postgres"

  engine         = "postgres"
  engine_version = var.engine_version
  instance_class = var.instance_class

  db_name  = var.db_name
  username = var.username
  password = var.password

  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.allocated_storage * 2   # storage autoscaling
  storage_type          = "gp3"
  storage_encrypted     = true

  multi_az               = var.multi_az
  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  parameter_group_name   = aws_db_parameter_group.this.name

  backup_retention_period = 7
  backup_window           = "03:00-04:00"
  maintenance_window      = "Mon:04:00-Mon:05:00"

  deletion_protection      = false   # true em produção real
  skip_final_snapshot      = true    # false em produção real
  delete_automated_backups = true

  performance_insights_enabled = true

  tags = {
    Name    = "${local.name_prefix}-postgres"
    Tier    = "data"
    Service = local.service_tag
  }
}
