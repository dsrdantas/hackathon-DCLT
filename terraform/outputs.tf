# ── VPC ───────────────────────────────────────────────────────
output "vpc_id" {
  description = "ID da VPC"
  value       = module.vpc.vpc_id
}

output "eks_subnet_ids" {
  description = "IDs das subnets privadas do EKS"
  value       = module.vpc.eks_subnet_ids
}

output "rds_subnet_ids" {
  description = "IDs das subnets compartilhadas pelo RDS"
  value       = module.vpc.rds_subnet_ids
}

# ── EKS ───────────────────────────────────────────────────────
output "eks_cluster_name" {
  description = "Nome do cluster EKS"
  value       = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  description = "Endpoint da API do cluster EKS"
  value       = module.eks.cluster_endpoint
}

output "eks_cluster_ca" {
  description = "Certificate Authority do cluster EKS"
  value       = module.eks.cluster_ca
  sensitive   = true
}

output "eks_kubeconfig_command" {
  description = "Comando para configurar o kubeconfig"
  value       = "aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${var.aws_region}"
}

# ── RDS — outputs agregados do for_each ───────────────────────
output "rds_endpoints" {
  description = "Endpoint de cada instância RDS (chave = nome do serviço)"
  value       = { for k, v in module.rds : k => v.endpoint }
}

output "rds_ports" {
  description = "Porta de cada instância RDS"
  value       = { for k, v in module.rds : k => v.port }
}

output "rds_security_group_ids" {
  description = "Security Group ID de cada instância RDS"
  value       = { for k, v in module.rds : k => v.security_group_id }
}

output "rds_connection_strings" {
  description = "DATABASE_URLs prontas para cada serviço (senha omitida)"
  value = {
    for k, v in module.rds :
    k => "postgres://${var.rds_username}:***@${v.endpoint}:${v.port}/${var.rds_instances[k].db_name}"
  }
}

# ── ElastiCache ───────────────────────────────────────────────
output "elasticache_endpoint" {
  description = "Endpoint primário do Redis"
  value       = module.elasticache.endpoint
}

output "elasticache_port" {
  description = "Porta do Redis"
  value       = module.elasticache.port
}

# ── SQS ───────────────────────────────────────────────────────
output "sqs_queue_url" {
  description = "URL da fila SQS solidary-donations"
  value       = module.sqs.queue_url
}

output "sqs_queue_arn" {
  description = "ARN da fila SQS"
  value       = module.sqs.queue_arn
}

# ── DynamoDB ──────────────────────────────────────────────────
output "dynamodb_table_name" {
  description = "Nome da tabela DynamoDB"
  value       = module.dynamodb.table_name
}

output "dynamodb_table_arn" {
  description = "ARN da tabela DynamoDB"
  value       = module.dynamodb.table_arn
}

# ── FinOps ────────────────────────────────────────────────────
output "finops_sns_topic_arn" {
  description = "ARN do tópico SNS de alertas de custo"
  value       = module.finops.sns_topic_arn
}

output "finops_cluster_autoscaler_policy_arn" {
  description = "ARN da policy IAM para o Cluster Autoscaler"
  value       = module.finops.cluster_autoscaler_policy_arn
}

# ── GitOps / ECR ──────────────────────────────────────────────
output "ecr_repository_urls" {
  description = "URLs dos repositórios ECR por serviço"
  value       = module.gitops.ecr_repository_urls
}

output "ecr_login_command" {
  description = "Comando para autenticar o Docker no ECR"
  value       = "aws ecr get-login-password --region ${var.aws_region} | docker login --username AWS --password-stdin <account-id>.dkr.ecr.${var.aws_region}.amazonaws.com"
}

output "argocd_initial_admin_secret_cmd" {
  description = "Comando para obter a senha inicial do admin do ArgoCD"
  value       = "kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 -d"
}

output "traefik_lb_hostname_cmd" {
  description = "Comando para obter o hostname do LoadBalancer do Traefik"
  value       = "kubectl get svc traefik -n traefik -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'"
}

# ── Secrets Manager ───────────────────────────────────────────
output "secrets_manager_names" {
  description = "Nomes dos secrets no AWS Secrets Manager por serviço"
  value = {
    ngo-service       = module.secrets.ngo_service_secret_name
    donation-service  = module.secrets.donation_service_secret_name
    volunteer-service = module.secrets.volunteer_service_secret_name
  }
}

output "secrets_manager_arns" {
  description = "ARNs dos secrets no AWS Secrets Manager"
  value = {
    ngo-service       = module.secrets.ngo_service_secret_arn
    donation-service  = module.secrets.donation_service_secret_arn
    volunteer-service = module.secrets.volunteer_service_secret_arn
  }
}

output "eso_verify_cmd" {
  description = "Comando para verificar se o ESO está lendo o Secrets Manager"
  value       = "kubectl get externalsecrets -A && kubectl get secrets -n ngo ngo-service-secrets -o jsonpath='{.data}' | base64 -d"
}
