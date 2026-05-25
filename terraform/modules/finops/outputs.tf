output "sns_topic_arn" { value = aws_sns_topic.cost_alerts.arn }
output "budget_total_id" { value = aws_budgets_budget.total.id }
output "budget_compute_id" { value = aws_budgets_budget.compute.id }
output "budget_data_id" { value = aws_budgets_budget.data.id }
output "budget_messaging_id" { value = aws_budgets_budget.messaging.id }
output "anomaly_monitor_arn" { value = aws_ce_anomaly_monitor.service.arn }
output "cluster_autoscaler_policy_arn" { value = aws_iam_policy.cluster_autoscaler.arn }
