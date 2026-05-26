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

# ════════════════════════════════════════════════════════════════
# VPC Endpoints
# ════════════════════════════════════════════════════════════════
data "aws_region" "current" {}

# ── Gateway Endpoints (sem custo por hora) ────────────────────
# Adicionam rotas diretas nas route tables; não usam DNS privado.
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
  route_table_ids   = [aws_route_table.private.id, aws_route_table.public.id]
  tags              = { Name = "${local.name_prefix}-vpce-s3" }
}

# ── Interface Endpoints (ENI privada nas subnets EKS) ─────────
# Permite que os nos EKS chamem EC2, ECR, EKS e STS diretamente
# pela rede privada AWS, sem depender do NAT Gateway.
#
# Requisito: enable_dns_support + enable_dns_hostnames habilitados
# na VPC (ambos ja estao ativos acima).
#
# Custo: ~$0.01/hora por endpoint por AZ + $0.01/GB dados.
# ═══════════════════════════════════════════════════════════════

# Security Group para as ENIs dos Interface Endpoints.
# Permite apenas HTTPS de dentro da VPC (stateful — respostas automaticas).
#trivy:ignore:AVD-AWS-0104 # VPCE SG: sem egress explicito = default all-outbound; stateful, respostas sao automaticas
resource "aws_security_group" "vpce" {
  name        = "${local.name_prefix}-vpce-sg"
  description = "HTTPS from VPC CIDR to Interface Endpoints"
  vpc_id      = aws_vpc.this.id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "HTTPS from VPC CIDR"
  }

  tags = { Name = "${local.name_prefix}-vpce-sg" }
}

# Mapa: chave do recurso Terraform → sufixo do service name AWS
locals {
  interface_endpoints = {
    "ec2"      = "ec2"       # EC2/DescribeInstances — bootstrap do nodeadm
    "eks"      = "eks"       # EKS API server — comunicacao kubelet/control-plane
    "eks-auth" = "eks-auth"  # EKS authentication — node join token
    "sts"      = "sts"       # IAM role assumption (LabRole)
    "ecr-api"  = "ecr.api"   # ECR API — manifest pull
    "ecr-dkr"  = "ecr.dkr"  # ECR Docker — layer pull (complementa S3 Gateway)
  }
}

# Um Interface Endpoint por servico, provisionado nas subnets EKS (2 AZs).
# private_dns_enabled = true: sobrescreve a resolucao DNS publica com
# o IP privado da ENI — os nos acessam a API sem sair da VPC.
resource "aws_vpc_endpoint" "interface" {
  for_each = local.interface_endpoints

  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.${each.value}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.eks[*].id
  security_group_ids  = [aws_security_group.vpce.id]
  private_dns_enabled = true

  tags = { Name = "${local.name_prefix}-vpce-${each.key}" }
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
