output "ngo_service_secret_arn" {
  description = "ARN do secret do ngo-service no Secrets Manager"
  value       = aws_secretsmanager_secret.ngo_service.arn
}

output "donation_service_secret_arn" {
  description = "ARN do secret do donation-service no Secrets Manager"
  value       = aws_secretsmanager_secret.donation_service.arn
}

output "volunteer_service_secret_arn" {
  description = "ARN do secret do volunteer-service no Secrets Manager"
  value       = aws_secretsmanager_secret.volunteer_service.arn
}

output "ngo_service_secret_name" {
  description = "Nome do secret do ngo-service no Secrets Manager"
  value       = aws_secretsmanager_secret.ngo_service.name
}

output "donation_service_secret_name" {
  description = "Nome do secret do donation-service no Secrets Manager"
  value       = aws_secretsmanager_secret.donation_service.name
}

output "volunteer_service_secret_name" {
  description = "Nome do secret do volunteer-service no Secrets Manager"
  value       = aws_secretsmanager_secret.volunteer_service.name
}
