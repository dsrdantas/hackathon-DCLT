# ── Projeto ───────────────────────────────────────────────────
project_name = "solidarytech"
environment  = "prod"
aws_region   = "us-east-1"

# ── Tags estruturadas — FinOps ────────────────────────────────
cost_center = "TC5-Hackathon"
team        = "platform-engineering"
owner_email = "dantas2dantas@msn.com"
repository  = "github.com/fiap/TC5-Hackathon-DCLT"

availability_zones = ["us-east-1a", "us-east-1b"]

# ── VPC ───────────────────────────────────────────────────────
vpc_cidr = "10.0.0.0/16"

# Subnets públicas (NAT Gateway e Load Balancers)
public_subnet_cidrs = ["10.0.0.0/24", "10.0.16.0/24"]

# Subnets privadas — uma por serviço, duplicadas por AZ (requisito AWS)
eks_subnet_cidrs         = ["10.0.1.0/24", "10.0.2.0/24"]
rds_subnet_cidrs         = ["10.0.3.0/24", "10.0.4.0/24"] # compartilhada por todos os bancos
elasticache_subnet_cidrs = ["10.0.5.0/24", "10.0.6.0/24"]

# ── EKS ───────────────────────────────────────────────────────
eks_version            = "1.33"
eks_node_instance_type = "t3.medium"
eks_min_nodes          = 2
eks_max_nodes          = 4
eks_desired_nodes      = 2

# ── RDS (PostgreSQL) ──────────────────────────────────────────
rds_engine_version = "16.3"
rds_username       = "tc5"
rds_password       = "supersenha" # ⚠️ Em produção real, use AWS Secrets Manager
rds_multi_az       = false        # true para produção com HA

# ── Instâncias RDS — for_each ─────────────────────────────────
# Para adicionar um banco: inclua uma nova entrada aqui.
# Cada chave vira parte do identifier: solidarytech-prod-<chave>-postgres
rds_instances = {
  ngo = {
    db_name           = "ngo_db"
    instance_class    = "db.t3.micro"
    allocated_storage = 20
  }
  donation = {
    db_name           = "donation_db"
    instance_class    = "db.t3.micro"
    allocated_storage = 20
  }
}

# ── ElastiCache (Redis) ───────────────────────────────────────
elasticache_node_type       = "cache.t3.micro"
elasticache_engine_version  = "7.1"
elasticache_num_cache_nodes = 1

# ── DynamoDB ──────────────────────────────────────────────────
dynamodb_table_name = "SolidaryTechVolunteers"

# ── SQS ───────────────────────────────────────────────────────
sqs_queue_name                 = "solidary-donations"
sqs_message_retention_seconds  = 86400 # 1 dia
sqs_visibility_timeout_seconds = 30

# ════════════════════════════════════════════════════════════════
# FinOps — Orçamentos mensais em USD
#
# Rightsizing recomendado (ajuste após análise do Compute Optimizer):
#   EKS nodes:   t3.medium → t3.small  se CPU médio < 20% por 7 dias
#   RDS:         db.t3.micro → db.t3.small  se conexões > 80% por 3 dias
#   ElastiCache: cache.t3.micro → cache.t3.small  se memória > 70%
# ════════════════════════════════════════════════════════════════

# Orçamento total mensal do projeto
budget_monthly_total = 500

# Orçamento por camada (soma das camadas ≤ budget_monthly_total)
budget_eks       = 250 # EC2 nodes + data transfer + control plane
budget_data      = 150 # RDS PostgreSQL + ElastiCache Redis
budget_messaging = 30  # SQS (por requisição) + DynamoDB (PAY_PER_REQUEST)

# Alertas em % do orçamento (ACTUAL): avisa em 80% e 100%
budget_alert_thresholds = [80, 100]

# Alerta de anomalia: dispara se aumento inesperado superar este valor
anomaly_threshold_usd = 20

# ── GitOps ────────────────────────────────────────────────────
gitops_repo_url        = "https://github.com/dsrdantas/hackathon-DCLT"
gitops_repo_branch     = "main"
argocd_chart_version   = "7.6.8"
traefik_chart_version  = "32.1.0"
gitops_services        = ["ngo-service", "donation-service", "volunteer-service"]
reloader_chart_version = "1.0.72"

# ── Observabilidade (Prometheus + Grafana + OTel + New Relic) ──
kube_prometheus_stack_chart_version = "65.1.1"
otel_collector_chart_version        = "0.108.0"
new_relic_endpoint                  = "https://otlp.nr-data.net" # US datacenter
