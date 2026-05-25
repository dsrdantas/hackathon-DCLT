# ── Projeto ───────────────────────────────────────────────────
variable "project_name" {
  description = "Nome do projeto (usado como prefixo nos recursos)"
  type        = string
}

variable "environment" {
  description = "Ambiente (prod | staging | dev)"
  type        = string
}

variable "aws_region" {
  description = "Região AWS"
  type        = string
}

variable "availability_zones" {
  description = "Lista de Availability Zones a utilizar"
  type        = list(string)
}

# ── Tags estruturadas (FinOps) ────────────────────────────────
variable "cost_center" {
  description = "Centro de custo para alocação financeira"
  type        = string
}

variable "team" {
  description = "Time responsável pelos recursos"
  type        = string
}

variable "owner_email" {
  description = "E-mail do responsável (usado em tags e alertas)"
  type        = string
}

variable "repository" {
  description = "URL do repositório de código fonte"
  type        = string
}

# ── FinOps — Budgets e Alertas ────────────────────────────────
variable "budget_monthly_total" {
  description = "Limite mensal total do projeto em USD"
  type        = number
}

variable "budget_eks" {
  description = "Limite mensal para camada compute (EKS) em USD"
  type        = number
}

variable "budget_data" {
  description = "Limite mensal para camada data (RDS + ElastiCache) em USD"
  type        = number
}

variable "budget_messaging" {
  description = "Limite mensal para camada messaging (SQS + DynamoDB) em USD"
  type        = number
}

variable "budget_alert_thresholds" {
  description = "Percentuais de alerta do budget (ACTUAL)"
  type        = list(number)
  default     = [80, 100]
}

variable "anomaly_threshold_usd" {
  description = "Valor mínimo em USD para alertar anomalia de custo"
  type        = number
}

# ── VPC ───────────────────────────────────────────────────────
variable "vpc_cidr" {
  description = "CIDR block da VPC"
  type        = string
}

variable "public_subnet_cidrs" {
  description = "CIDRs das subnets públicas (NAT Gateway / Load Balancer)"
  type        = list(string)
}

variable "eks_subnet_cidrs" {
  description = "CIDRs das subnets privadas do EKS (uma por AZ)"
  type        = list(string)
}

variable "rds_subnet_cidrs" {
  description = "CIDRs das subnets privadas compartilhadas pelos bancos RDS (uma por AZ)"
  type        = list(string)
}

variable "elasticache_subnet_cidrs" {
  description = "CIDRs das subnets privadas do ElastiCache (uma por AZ)"
  type        = list(string)
}

# ── EKS ───────────────────────────────────────────────────────
variable "eks_version" {
  description = "Versão do Kubernetes no cluster EKS"
  type        = string
}

variable "eks_node_instance_type" {
  description = "Tipo de instância EC2 para os nós do EKS"
  type        = string
}

variable "eks_min_nodes" {
  description = "Número mínimo de nós no node group"
  type        = number
}

variable "eks_max_nodes" {
  description = "Número máximo de nós no node group"
  type        = number
}

variable "eks_desired_nodes" {
  description = "Número desejado de nós no node group"
  type        = number
}

# ── RDS ───────────────────────────────────────────────────────
variable "rds_instances" {
  description = <<-EOT
    Mapa de instâncias RDS a criar.
    Chave = nome do serviço (vira parte do identifier e das tags).
    Para adicionar um banco: basta incluir uma nova entrada no tfvars.
  EOT
  type = map(object({
    db_name           = string
    instance_class    = string
    allocated_storage = number
  }))
}

variable "rds_engine_version" {
  description = "Versão do PostgreSQL (compartilhada por todas as instâncias)"
  type        = string
}

variable "rds_username" {
  description = "Usuário administrador (compartilhado por todas as instâncias)"
  type        = string
}

variable "rds_password" {
  description = "Senha do usuário administrador"
  type        = string
  sensitive   = true
}

variable "rds_multi_az" {
  description = "Habilitar Multi-AZ em todas as instâncias RDS"
  type        = bool
}

# ── ElastiCache ───────────────────────────────────────────────
variable "elasticache_node_type" {
  description = "Tipo de nó do ElastiCache (Redis)"
  type        = string
}

variable "elasticache_engine_version" {
  description = "Versão do Redis"
  type        = string
}

variable "elasticache_num_cache_nodes" {
  description = "Número de nós do cluster Redis"
  type        = number
}

# ── DynamoDB ──────────────────────────────────────────────────
variable "dynamodb_table_name" {
  description = "Nome da tabela DynamoDB para voluntários"
  type        = string
}

# ── SQS ───────────────────────────────────────────────────────
variable "sqs_queue_name" {
  description = "Nome da fila SQS para doações"
  type        = string
}

variable "sqs_message_retention_seconds" {
  description = "Tempo de retenção das mensagens na fila (segundos)"
  type        = number
}

variable "sqs_visibility_timeout_seconds" {
  description = "Timeout de visibilidade das mensagens (segundos)"
  type        = number
}

# ── GitOps ────────────────────────────────────────────────────
variable "gitops_repo_url" {
  description = "URL do repositório Git monitorado pelo ArgoCD"
  type        = string
  default     = "https://github.com/dsrdantas/hackathon-DCLT"
}

variable "gitops_repo_branch" {
  description = "Branch monitorada pelo ArgoCD"
  type        = string
  default     = "main"
}

variable "argocd_chart_version" {
  description = "Versão do chart Helm do ArgoCD"
  type        = string
  default     = "7.6.8"
}

variable "traefik_chart_version" {
  description = "Versão do chart Helm do Traefik"
  type        = string
  default     = "32.1.0"
}

variable "gitops_services" {
  description = "Lista de microserviços com repositórios ECR a criar"
  type        = list(string)
  default     = ["ngo-service", "donation-service", "volunteer-service"]
}

variable "reloader_chart_version" {
  description = "Versão do chart Helm do Stakater Reloader"
  type        = string
  default     = "1.0.72"
}

variable "kube_prometheus_stack_chart_version" {
  description = "Versão do chart kube-prometheus-stack (Prometheus + Grafana + AlertManager)"
  type        = string
  default     = "65.1.1"
}

variable "otel_collector_chart_version" {
  description = "Versão do chart OpenTelemetry Collector"
  type        = string
  default     = "0.108.0"
}

variable "new_relic_endpoint" {
  description = "Endpoint OTLP do New Relic (US ou EU)"
  type        = string
  default     = "https://otlp.nr-data.net"
}
