output "ecr_repository_urls" {
  description = "URLs dos repositórios ECR por serviço"
  value       = { for k, v in aws_ecr_repository.services : k => v.repository_url }
}

output "ecr_repository_arns" {
  description = "ARNs dos repositórios ECR por serviço"
  value       = { for k, v in aws_ecr_repository.services : k => v.arn }
}

output "argocd_namespace" {
  description = "Namespace onde o ArgoCD foi instalado"
  value       = kubernetes_namespace.argocd.metadata[0].name
}

output "traefik_namespace" {
  description = "Namespace onde o Traefik foi instalado"
  value       = kubernetes_namespace.traefik.metadata[0].name
}

output "argocd_chart_version" {
  description = "Versão do chart ArgoCD instalado"
  value       = helm_release.argocd.version
}

output "traefik_chart_version" {
  description = "Versão do chart Traefik instalado"
  value       = helm_release.traefik.version
}

output "external_secrets_namespace" {
  description = "Namespace onde o External Secrets Operator foi instalado"
  value       = kubernetes_namespace.external_secrets.metadata[0].name
}

output "eso_chart_version" {
  description = "Versão do chart External Secrets Operator instalado"
  value       = helm_release.external_secrets.version
}
