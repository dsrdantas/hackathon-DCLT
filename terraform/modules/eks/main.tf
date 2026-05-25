locals {
  cluster_name = "${var.project_name}-${var.environment}-eks"
}

# ════════════════════════════════════════════════════════════════
# IAM — AWS Academy LabRole (pre-existente)
#
# ⚠️  AWS Academy LabRole NÃO permite iam:CreateRole nem iam:CreatePolicy.
#     Usamos o LabRole pré-provisionado como cluster role E node role.
#     O LabRole já possui todas as políticas necessárias:
#       AmazonEKSClusterPolicy, AmazonEKSWorkerNodePolicy,
#       AmazonEKS_CNI_Policy, AmazonEC2ContainerRegistryReadOnly,
#       AmazonSSMManagedInstanceCore, acesso a SQS e DynamoDB.
# ════════════════════════════════════════════════════════════════
data "aws_iam_role" "lab_role" {
  name = "LabRole"
}

# ════════════════════════════════════════════════════════════════
# Security Groups
# ════════════════════════════════════════════════════════════════
#trivy:ignore:AVD-AWS-0104 # EKS control-plane SG: egress to internet necessário para acesso ao ECR e APIs AWS
resource "aws_security_group" "cluster" {
  name        = "${local.cluster_name}-cluster-sg"
  description = "Control plane EKS - comunicacao com nos"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound - required for ECR pull and AWS API access"
  }

  tags = { Name = "${local.cluster_name}-cluster-sg" }
}

#trivy:ignore:AVD-AWS-0104 # Node SG: egress a internet necessário para ECR pull, AWS API e atualização de sistema
resource "aws_security_group" "nodes" {
  name        = "${local.cluster_name}-nodes-sg"
  description = "Nos do EKS - comunicacao interna e com control plane"
  vpc_id      = var.vpc_id

  # Comunicação intra-cluster
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
    description = "Node-to-node communication"
  }

  # Control plane → nós (webhook, metrics, etc.)
  ingress {
    from_port       = 1025
    to_port         = 65535
    protocol        = "tcp"
    security_groups = [aws_security_group.cluster.id]
    description     = "Control plane to nodes"
  }

  # HTTPS do control plane para os nós
  ingress {
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.cluster.id]
    description     = "Control plane HTTPS to nodes"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound"
  }

  tags = { Name = "${local.cluster_name}-nodes-sg" }
}

# Nós → control plane (HTTPS)
resource "aws_security_group_rule" "cluster_ingress_nodes" {
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  security_group_id        = aws_security_group.cluster.id
  source_security_group_id = aws_security_group.nodes.id
  description              = "Nodes to control plane HTTPS"
}

# ════════════════════════════════════════════════════════════════
# EKS Cluster
# ════════════════════════════════════════════════════════════════
#trivy:ignore:AVD-AWS-0039 # KMS secret encryption omitido: AWS Academy LabRole não permite criar CMKs
#trivy:ignore:AVD-AWS-0040 # Endpoint público necessário: GitHub Actions precisa de acesso kubectl sem VPN
#trivy:ignore:AVD-AWS-0041 # CIDR 0.0.0.0/0: IPs do GitHub Actions são dinâmicos; restringir via OIDC em produção real
resource "aws_eks_cluster" "this" {
  name     = local.cluster_name
  role_arn = data.aws_iam_role.lab_role.arn
  version  = var.eks_version

  vpc_config {
    subnet_ids              = var.subnet_ids
    security_group_ids      = [aws_security_group.cluster.id]
    endpoint_private_access = true
    endpoint_public_access  = true
  }

  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  tags = { Name = local.cluster_name, Tier = "compute", Service = "eks-kubernetes" }
}

# ════════════════════════════════════════════════════════════════
# Add-ons essenciais
# ════════════════════════════════════════════════════════════════
resource "aws_eks_addon" "vpc_cni" {
  cluster_name = aws_eks_cluster.this.name
  addon_name   = "vpc-cni"
}

resource "aws_eks_addon" "coredns" {
  cluster_name = aws_eks_cluster.this.name
  addon_name   = "coredns"
  depends_on   = [aws_eks_node_group.this]
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name = aws_eks_cluster.this.name
  addon_name   = "kube-proxy"
}

# ════════════════════════════════════════════════════════════════
# Node Group (Managed)
# ════════════════════════════════════════════════════════════════
resource "aws_eks_node_group" "this" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${local.cluster_name}-nodes"
  node_role_arn   = data.aws_iam_role.lab_role.arn
  subnet_ids      = var.subnet_ids

  instance_types = [var.eks_node_instance_type]

  scaling_config {
    min_size     = var.eks_min_nodes
    max_size     = var.eks_max_nodes
    desired_size = var.eks_desired_nodes
  }

  update_config {
    max_unavailable = 1
  }

  launch_template {
    id      = aws_launch_template.nodes.id
    version = aws_launch_template.nodes.latest_version
  }

  tags = {
    Name    = "${local.cluster_name}-nodes"
    Tier    = "compute"
    Service = "eks-kubernetes"
    # Tags obrigatórias para o Cluster Autoscaler descobrir o node group
    "k8s.io/cluster-autoscaler/enabled"               = "true"
    "k8s.io/cluster-autoscaler/${local.cluster_name}" = "owned"
  }
}

resource "aws_launch_template" "nodes" {
  name_prefix = "${local.cluster_name}-lt-"

  vpc_security_group_ids = [aws_security_group.nodes.id]

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required" # IMDSv2
    http_put_response_hop_limit = 2
  }

  tag_specifications {
    resource_type = "instance"
    tags          = { Name = "${local.cluster_name}-node" }
  }
}
