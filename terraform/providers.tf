# ════════════════════════════════════════════════════════════════
# providers.tf — Providers Helm e Kubernetes
#
# IMPORTANTE — Ordem de apply em ambiente novo (primeiro deploy):
#
#   1. terraform apply -target=module.eks
#      Cria o cluster EKS; os providers abaixo precisam do endpoint.
#
#   2. terraform apply
#      Instala ArgoCD, Traefik, metrics-server e faz o bootstrap.
#
# Em pipelines CI/CD (cluster já existe), um único `terraform apply`
# é suficiente — os data sources resolvem o cluster existente.
# ════════════════════════════════════════════════════════════════

# ── Data sources: resolve credenciais do cluster EKS ─────────
data "aws_eks_cluster" "this" {
  name = module.eks.cluster_name
}

data "aws_eks_cluster_auth" "this" {
  name = module.eks.cluster_name
}

# ── Provider Helm ─────────────────────────────────────────────
provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.this.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.this.token
  }
}

# ── Provider Kubernetes ───────────────────────────────────────
provider "kubernetes" {
  host                   = data.aws_eks_cluster.this.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.this.token
}
