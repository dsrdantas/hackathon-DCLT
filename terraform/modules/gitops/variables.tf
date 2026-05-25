variable "project_name" {
  description = "Nome do projeto (prefixo dos recursos)"
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

variable "cluster_name" {
  description = "Nome do cluster EKS"
  type        = string
}

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

variable "metrics_server_chart_version" {
  description = "Versão do chart Helm do metrics-server (necessário para HPA)"
  type        = string
  default     = "3.12.1"
}

variable "services" {
  description = "Lista de microserviços para criar repositórios ECR"
  type        = list(string)
  default     = ["ngo-service", "donation-service", "volunteer-service"]
}

variable "ecr_image_retention_count" {
  description = "Número máximo de imagens retidas por repositório ECR"
  type        = number
  default     = 10
}

variable "eso_chart_version" {
  description = "Versão do chart Helm do External Secrets Operator"
  type        = string
  default     = "0.10.3"
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

variable "tags" {
  description = "Tags a aplicar nos recursos gerenciados"
  type        = map(string)
  default     = {}
}
