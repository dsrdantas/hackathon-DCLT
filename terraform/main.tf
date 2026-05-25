# ── FinOps — Budgets, Alertas, Rightsizing ───────────────────
module "finops" {
  source = "./modules/finops"

  project_name   = var.project_name
  environment    = var.environment
  aws_region     = var.aws_region
  alert_email    = var.owner_email
  tags           = local.tags_finops

  budget_monthly_total    = var.budget_monthly_total
  budget_eks              = var.budget_eks
  budget_data             = var.budget_data
  budget_messaging        = var.budget_messaging
  budget_alert_thresholds = var.budget_alert_thresholds
  anomaly_threshold_usd   = var.anomaly_threshold_usd
}

# ── VPC ───────────────────────────────────────────────────────
module "vpc" {
  source = "./modules/vpc"

  project_name             = var.project_name
  environment              = var.environment
  vpc_cidr                 = var.vpc_cidr
  availability_zones       = var.availability_zones
  public_subnet_cidrs      = var.public_subnet_cidrs
  eks_subnet_cidrs         = var.eks_subnet_cidrs
  rds_subnet_cidrs         = var.rds_subnet_cidrs
  elasticache_subnet_cidrs = var.elasticache_subnet_cidrs
}

# ── EKS ───────────────────────────────────────────────────────
module "eks" {
  source = "./modules/eks"

  project_name           = var.project_name
  environment            = var.environment
  eks_version            = var.eks_version
  vpc_id                 = module.vpc.vpc_id
  subnet_ids             = module.vpc.eks_subnet_ids
  eks_node_instance_type = var.eks_node_instance_type
  eks_min_nodes          = var.eks_min_nodes
  eks_max_nodes          = var.eks_max_nodes
  eks_desired_nodes      = var.eks_desired_nodes
}

# ── RDS — for_each: uma instância por entrada no mapa ─────────
# Para adicionar um novo banco: apenas edite rds_instances no tfvars
module "rds" {
  source   = "./modules/rds"
  for_each = var.rds_instances

  project_name      = var.project_name
  environment       = var.environment
  service_name      = each.key               # "ngo" | "donation" | ...
  vpc_id            = module.vpc.vpc_id
  subnet_ids        = module.vpc.rds_subnet_ids
  eks_sg_id         = module.eks.node_security_group_id
  instance_class    = each.value.instance_class
  engine_version    = var.rds_engine_version
  db_name           = each.value.db_name
  username          = var.rds_username
  password          = var.rds_password
  allocated_storage = each.value.allocated_storage
  multi_az          = var.rds_multi_az
}

# ── ElastiCache ───────────────────────────────────────────────
module "elasticache" {
  source = "./modules/elasticache"

  project_name    = var.project_name
  environment     = var.environment
  vpc_id          = module.vpc.vpc_id
  subnet_ids      = module.vpc.elasticache_subnet_ids
  eks_sg_id       = module.eks.node_security_group_id
  node_type       = var.elasticache_node_type
  engine_version  = var.elasticache_engine_version
  num_cache_nodes = var.elasticache_num_cache_nodes
}

# ── SQS ───────────────────────────────────────────────────────
module "sqs" {
  source = "./modules/sqs"

  project_name                   = var.project_name
  environment                    = var.environment
  queue_name                     = var.sqs_queue_name
  eks_node_role_arn              = module.eks.node_role_arn
  message_retention_seconds      = var.sqs_message_retention_seconds
  visibility_timeout_seconds     = var.sqs_visibility_timeout_seconds
}

# ── DynamoDB ──────────────────────────────────────────────────
module "dynamodb" {
  source = "./modules/dynamodb"

  project_name      = var.project_name
  environment       = var.environment
  table_name        = var.dynamodb_table_name
  eks_node_role_arn = module.eks.node_role_arn
}

# ── Secrets Manager + IAM role ESO (IRSA) ────────────────────
# Cria os secrets de cada serviço com valores dos outputs do Terraform,
# e a IAM role para o External Secrets Operator acessar o SM via IRSA.
module "secrets" {
  source = "./modules/secrets"

  project_name = var.project_name
  environment  = var.environment
  aws_region   = var.aws_region

  # RDS — valores extraídos dos outputs do módulo rds
  rds_username  = var.rds_username
  rds_password  = var.rds_password
  rds_endpoints = { for k, v in module.rds : k => v.endpoint }
  rds_ports     = { for k, v in module.rds : k => v.port }
  rds_db_names  = { for k, v in var.rds_instances : k => v.db_name }

  # SQS e DynamoDB
  sqs_queue_url       = module.sqs.queue_url
  dynamodb_table_name = var.dynamodb_table_name

  tags = local.tags_data

  depends_on = [module.rds, module.sqs, module.eks]
}

# ── GitOps — ECR + ArgoCD + Traefik + ESO + Bootstrap ────────
# Pré-requisito: execute `terraform apply -target=module.eks` antes
# da primeira execução completa deste módulo.
module "gitops" {
  source = "./modules/gitops"

  project_name          = var.project_name
  environment           = var.environment
  aws_region            = var.aws_region
  cluster_name          = module.eks.cluster_name
  gitops_repo_url       = var.gitops_repo_url
  gitops_repo_branch    = var.gitops_repo_branch
  argocd_chart_version                = var.argocd_chart_version
  traefik_chart_version               = var.traefik_chart_version
  reloader_chart_version              = var.reloader_chart_version
  kube_prometheus_stack_chart_version = var.kube_prometheus_stack_chart_version
  otel_collector_chart_version        = var.otel_collector_chart_version
  new_relic_endpoint                  = var.new_relic_endpoint
  services                            = var.gitops_services
  tags                                = local.tags_compute

  depends_on = [module.eks, module.secrets]
}
