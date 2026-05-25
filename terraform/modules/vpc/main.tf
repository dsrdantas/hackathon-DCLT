locals {
  name_prefix  = "${var.project_name}-${var.environment}"
  cluster_name = "${var.project_name}-${var.environment}-eks"
}

# ── VPC ───────────────────────────────────────────────────────
resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${local.name_prefix}-vpc", Tier = "network", Service = "vpc-networking" }
}

# ── Internet Gateway ──────────────────────────────────────────
resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${local.name_prefix}-igw" }
}

# ── Subnets públicas (NAT Gateway + Load Balancers) ──────────
#trivy:ignore:AVD-AWS-0164 # Subnets públicas precisam de IP público para Load Balancers e NAT Gateway
resource "aws_subnet" "public" {
  count                   = length(var.public_subnet_cidrs)
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name                                          = "${local.name_prefix}-public-${count.index + 1}"
    "kubernetes.io/role/elb"                      = "1"
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
  }
}

# ── Subnets privadas — EKS ────────────────────────────────────
resource "aws_subnet" "eks" {
  count             = length(var.eks_subnet_cidrs)
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.eks_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = {
    Name                                          = "${local.name_prefix}-eks-${count.index + 1}"
    "kubernetes.io/role/internal-elb"             = "1"
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
  }
}

# ── Subnets privadas — RDS (compartilhada por todos os bancos) ─
resource "aws_subnet" "rds" {
  count             = length(var.rds_subnet_cidrs)
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.rds_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = { Name = "${local.name_prefix}-rds-${count.index + 1}", Tier = "data", Service = "rds-postgresql" }
}

# ── Subnets privadas — ElastiCache ───────────────────────────
resource "aws_subnet" "elasticache" {
  count             = length(var.elasticache_subnet_cidrs)
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.elasticache_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = { Name = "${local.name_prefix}-elasticache-${count.index + 1}", Tier = "cache", Service = "elasticache-redis" }
}

# ── NAT Gateway ───────────────────────────────────────────────
resource "aws_eip" "nat" {
  domain = "vpc"
  tags   = { Name = "${local.name_prefix}-nat-eip" }
}

resource "aws_nat_gateway" "this" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id
  depends_on    = [aws_internet_gateway.this]
  tags          = { Name = "${local.name_prefix}-nat" }
}

# ── Route Tables ──────────────────────────────────────────────
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }
  tags = { Name = "${local.name_prefix}-rt-public" }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.this.id
  }
  tags = { Name = "${local.name_prefix}-rt-private" }
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "eks" {
  count          = length(aws_subnet.eks)
  subnet_id      = aws_subnet.eks[count.index].id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "rds" {
  count          = length(aws_subnet.rds)
  subnet_id      = aws_subnet.rds[count.index].id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "elasticache" {
  count          = length(aws_subnet.elasticache)
  subnet_id      = aws_subnet.elasticache[count.index].id
  route_table_id = aws_route_table.private.id
}

# ── VPC Endpoints gratuitos (gateway) ────────────────────────
data "aws_region" "current" {}

resource "aws_vpc_endpoint" "dynamodb" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.dynamodb"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id]
  tags              = { Name = "${local.name_prefix}-vpce-dynamodb" }
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id]
  tags              = { Name = "${local.name_prefix}-vpce-s3" }
}

# ════════════════════════════════════════════════════════════════
# NACLs — Stateless: inbound E outbound obrigatórios
# ════════════════════════════════════════════════════════════════

# ── NACL Pública ──────────────────────────────────────────────
resource "aws_network_acl" "public" {
  vpc_id     = aws_vpc.this.id
  subnet_ids = aws_subnet.public[*].id
  tags       = { Name = "${local.name_prefix}-nacl-public" }
}

resource "aws_network_acl_rule" "public_in_http" {
  network_acl_id = aws_network_acl.public.id
  rule_number    = 100
  protocol       = "tcp"
  rule_action    = "allow"
  egress         = false
  cidr_block     = "0.0.0.0/0"
  from_port      = 80
  to_port        = 80
}
resource "aws_network_acl_rule" "public_in_https" {
  network_acl_id = aws_network_acl.public.id
  rule_number    = 110
  protocol       = "tcp"
  rule_action    = "allow"
  egress         = false
  cidr_block     = "0.0.0.0/0"
  from_port      = 443
  to_port        = 443
}
resource "aws_network_acl_rule" "public_in_ephemeral" {
  network_acl_id = aws_network_acl.public.id
  rule_number    = 120
  protocol       = "tcp"
  rule_action    = "allow"
  egress         = false
  cidr_block     = "0.0.0.0/0"
  from_port      = 1024
  to_port        = 65535
}
#trivy:ignore:AVD-AWS-0102 # NACL público: egress amplo necessário para resposta a clientes HTTP/S e tráfego de saída do NAT
resource "aws_network_acl_rule" "public_out_all" {
  network_acl_id = aws_network_acl.public.id
  rule_number    = 100
  protocol       = "-1"
  rule_action    = "allow"
  egress         = true
  cidr_block     = "0.0.0.0/0"
  from_port      = 0
  to_port        = 0
}

# ── NACL EKS ──────────────────────────────────────────────────
resource "aws_network_acl" "eks" {
  vpc_id     = aws_vpc.this.id
  subnet_ids = aws_subnet.eks[*].id
  tags       = { Name = "${local.name_prefix}-nacl-eks" }
}

#trivy:ignore:AVD-AWS-0102 # NACL EKS inbound: protocolo -1 necessário para comunicação intra-VPC (todos os protocolos Kubernetes)
resource "aws_network_acl_rule" "eks_in_vpc" {
  network_acl_id = aws_network_acl.eks.id
  rule_number    = 100
  protocol       = "-1"
  rule_action    = "allow"
  egress         = false
  cidr_block     = var.vpc_cidr
  from_port      = 0
  to_port        = 0
}
resource "aws_network_acl_rule" "eks_in_ephemeral" {
  network_acl_id = aws_network_acl.eks.id
  rule_number    = 110
  protocol       = "tcp"
  rule_action    = "allow"
  egress         = false
  cidr_block     = "0.0.0.0/0"
  from_port      = 1024
  to_port        = 65535
}
#trivy:ignore:AVD-AWS-0102 # NACL EKS outbound: protocolo -1 necessário para ECR pull, AWS APIs e comunicação intra-cluster
resource "aws_network_acl_rule" "eks_out_all" {
  network_acl_id = aws_network_acl.eks.id
  rule_number    = 100
  protocol       = "-1"
  rule_action    = "allow"
  egress         = true
  cidr_block     = "0.0.0.0/0"
  from_port      = 0
  to_port        = 0
}

# ── NACL RDS — subnet compartilhada por todos os bancos ───────
resource "aws_network_acl" "rds" {
  vpc_id     = aws_vpc.this.id
  subnet_ids = aws_subnet.rds[*].id
  tags       = { Name = "${local.name_prefix}-nacl-rds", Tier = "data", Service = "rds-postgresql" }
}

# Inbound: somente PostgreSQL e efêmeras vindas da VPC (EKS)
resource "aws_network_acl_rule" "rds_in_postgres" {
  network_acl_id = aws_network_acl.rds.id
  rule_number    = 100
  protocol       = "tcp"
  rule_action    = "allow"
  egress         = false
  cidr_block     = var.vpc_cidr
  from_port      = 5432
  to_port        = 5432
}
resource "aws_network_acl_rule" "rds_in_ephemeral" {
  network_acl_id = aws_network_acl.rds.id
  rule_number    = 110
  protocol       = "tcp"
  rule_action    = "allow"
  egress         = false
  cidr_block     = var.vpc_cidr
  from_port      = 1024
  to_port        = 65535
}

# Outbound: respostas TCP de volta para a VPC
resource "aws_network_acl_rule" "rds_out_ephemeral" {
  network_acl_id = aws_network_acl.rds.id
  rule_number    = 100
  protocol       = "tcp"
  rule_action    = "allow"
  egress         = true
  cidr_block     = var.vpc_cidr
  from_port      = 1024
  to_port        = 65535
}

# ── NACL ElastiCache ──────────────────────────────────────────
resource "aws_network_acl" "elasticache" {
  vpc_id     = aws_vpc.this.id
  subnet_ids = aws_subnet.elasticache[*].id
  tags       = { Name = "${local.name_prefix}-nacl-elasticache" }
}

resource "aws_network_acl_rule" "ec_in_redis" {
  network_acl_id = aws_network_acl.elasticache.id
  rule_number    = 100
  protocol       = "tcp"
  rule_action    = "allow"
  egress         = false
  cidr_block     = var.vpc_cidr
  from_port      = 6379
  to_port        = 6379
}
resource "aws_network_acl_rule" "ec_in_ephemeral" {
  network_acl_id = aws_network_acl.elasticache.id
  rule_number    = 110
  protocol       = "tcp"
  rule_action    = "allow"
  egress         = false
  cidr_block     = var.vpc_cidr
  from_port      = 1024
  to_port        = 65535
}
resource "aws_network_acl_rule" "ec_out_ephemeral" {
  network_acl_id = aws_network_acl.elasticache.id
  rule_number    = 100
  protocol       = "tcp"
  rule_action    = "allow"
  egress         = true
  cidr_block     = var.vpc_cidr
  from_port      = 1024
  to_port        = 65535
}
