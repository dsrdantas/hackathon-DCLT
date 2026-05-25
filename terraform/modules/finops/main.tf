locals {
  name_prefix       = "${var.project_name}-${var.environment}"
  budget_start_date = "2026-01-01_00:00"
}

# ════════════════════════════════════════════════════════════════
# SNS — Canal de notificações de custo
# ════════════════════════════════════════════════════════════════
#trivy:ignore:AVD-AWS-0095 # SNS de alertas de custo: dados não sensíveis; CMK omitido pois AWS Academy LabRole não permite criar KMS keys
resource "aws_sns_topic" "cost_alerts" {
  name = "${local.name_prefix}-cost-alerts"
  tags = merge(var.tags, { Name = "${local.name_prefix}-cost-alerts" })
}

# Permite que AWS Budgets e Cost Anomaly Detection publiquem no tópico
resource "aws_sns_topic_policy" "cost_alerts" {
  arn = aws_sns_topic.cost_alerts.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowBudgetsPublish"
        Effect    = "Allow"
        Principal = { Service = "budgets.amazonaws.com" }
        Action    = "SNS:Publish"
        Resource  = aws_sns_topic.cost_alerts.arn
      },
      {
        Sid       = "AllowAnomalyDetectionPublish"
        Effect    = "Allow"
        Principal = { Service = "costalerts.amazonaws.com" }
        Action    = "SNS:Publish"
        Resource  = aws_sns_topic.cost_alerts.arn
      }
    ]
  })
}

# Subscrição por e-mail (requer confirmação manual na caixa de entrada)
resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.cost_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# ════════════════════════════════════════════════════════════════
# AWS Budgets — Orçamentos por camada
# ════════════════════════════════════════════════════════════════

# ── Budget 1: Custo total mensal do projeto ───────────────────
resource "aws_budgets_budget" "total" {
  name              = "${local.name_prefix}-total-mensal"
  budget_type       = "COST"
  limit_amount      = tostring(var.budget_monthly_total)
  limit_unit        = "USD"
  time_unit         = "MONTHLY"
  time_period_start = local.budget_start_date

  # Alerta ACTUAL em cada threshold configurado
  dynamic "notification" {
    for_each = var.budget_alert_thresholds
    content {
      comparison_operator       = "GREATER_THAN"
      threshold                 = notification.value
      threshold_type            = "PERCENTAGE"
      notification_type         = "ACTUAL"
      subscriber_sns_topic_arns = [aws_sns_topic.cost_alerts.arn]
    }
  }

  # Alerta FORECASTED — avisa antes de estourar
  notification {
    comparison_operator       = "GREATER_THAN"
    threshold                 = 100
    threshold_type            = "PERCENTAGE"
    notification_type         = "FORECASTED"
    subscriber_sns_topic_arns = [aws_sns_topic.cost_alerts.arn]
  }

  tags = var.tags
}

# ── Budget 2: Camada Compute (EKS) — filtrado por tag Tier ───
resource "aws_budgets_budget" "compute" {
  name              = "${local.name_prefix}-compute-eks"
  budget_type       = "COST"
  limit_amount      = tostring(var.budget_eks)
  limit_unit        = "USD"
  time_unit         = "MONTHLY"
  time_period_start = local.budget_start_date

  # Filtra gastos de recursos com tag Tier=compute
  # ⚠️ Tags de alocação de custo devem ser ativadas no AWS Billing Console
  cost_filter {
    name   = "TagKeyValue"
    values = ["user:Tier$compute"]
  }

  dynamic "notification" {
    for_each = var.budget_alert_thresholds
    content {
      comparison_operator       = "GREATER_THAN"
      threshold                 = notification.value
      threshold_type            = "PERCENTAGE"
      notification_type         = "ACTUAL"
      subscriber_sns_topic_arns = [aws_sns_topic.cost_alerts.arn]
    }
  }

  notification {
    comparison_operator       = "GREATER_THAN"
    threshold                 = 100
    threshold_type            = "PERCENTAGE"
    notification_type         = "FORECASTED"
    subscriber_sns_topic_arns = [aws_sns_topic.cost_alerts.arn]
  }

  tags = var.tags
}

# ── Budget 3: Camada Data (RDS + ElastiCache) ────────────────
resource "aws_budgets_budget" "data" {
  name              = "${local.name_prefix}-data-rds-cache"
  budget_type       = "COST"
  limit_amount      = tostring(var.budget_data)
  limit_unit        = "USD"
  time_unit         = "MONTHLY"
  time_period_start = local.budget_start_date

  cost_filter {
    name   = "TagKeyValue"
    values = ["user:Tier$data", "user:Tier$cache"]
  }

  dynamic "notification" {
    for_each = var.budget_alert_thresholds
    content {
      comparison_operator       = "GREATER_THAN"
      threshold                 = notification.value
      threshold_type            = "PERCENTAGE"
      notification_type         = "ACTUAL"
      subscriber_sns_topic_arns = [aws_sns_topic.cost_alerts.arn]
    }
  }

  notification {
    comparison_operator       = "GREATER_THAN"
    threshold                 = 100
    threshold_type            = "PERCENTAGE"
    notification_type         = "FORECASTED"
    subscriber_sns_topic_arns = [aws_sns_topic.cost_alerts.arn]
  }

  tags = var.tags
}

# ── Budget 4: Camada Messaging (SQS + DynamoDB) ──────────────
resource "aws_budgets_budget" "messaging" {
  name              = "${local.name_prefix}-messaging-sqs-dynamo"
  budget_type       = "COST"
  limit_amount      = tostring(var.budget_messaging)
  limit_unit        = "USD"
  time_unit         = "MONTHLY"
  time_period_start = local.budget_start_date

  cost_filter {
    name   = "TagKeyValue"
    values = ["user:Tier$messaging"]
  }

  dynamic "notification" {
    for_each = var.budget_alert_thresholds
    content {
      comparison_operator       = "GREATER_THAN"
      threshold                 = notification.value
      threshold_type            = "PERCENTAGE"
      notification_type         = "ACTUAL"
      subscriber_sns_topic_arns = [aws_sns_topic.cost_alerts.arn]
    }
  }

  tags = var.tags
}

# ════════════════════════════════════════════════════════════════
# Cost Anomaly Detection
# Detecta picos inesperados de custo por serviço AWS
# ════════════════════════════════════════════════════════════════
resource "aws_ce_anomaly_monitor" "service" {
  name              = "${local.name_prefix}-anomaly-monitor"
  monitor_type      = "DIMENSIONAL"
  monitor_dimension = "SERVICE"
  tags              = var.tags
}

resource "aws_ce_anomaly_subscription" "daily" {
  name      = "${local.name_prefix}-anomaly-daily"
  frequency = "DAILY"

  monitor_arn_list = [aws_ce_anomaly_monitor.service.arn]

  subscriber {
    type    = "SNS"
    address = aws_sns_topic.cost_alerts.arn
  }

  threshold_expression {
    dimension {
      key           = "ANOMALY_TOTAL_IMPACT_ABSOLUTE"
      match_options = ["GREATER_THAN_OR_EQUAL"]
      values        = [tostring(var.anomaly_threshold_usd)]
    }
  }

  tags = var.tags
}

# ════════════════════════════════════════════════════════════════
# AWS Compute Optimizer
# Analisa uso de EC2 (nós EKS), RDS, ElastiCache e gera
# recomendações de rightsizing automaticamente
# ════════════════════════════════════════════════════════════════
resource "aws_computeoptimizer_enrollment_status" "this" {
  status = "Active"
}

# ════════════════════════════════════════════════════════════════
# IAM Policy — Cluster Autoscaler (EKS)
# Permite que o Cluster Autoscaler ajuste o tamanho dos node groups
# Deploy via Helm após criação do cluster
# ════════════════════════════════════════════════════════════════
resource "aws_iam_policy" "cluster_autoscaler" {
  name        = "${local.name_prefix}-cluster-autoscaler"
  description = "Permite ao Cluster Autoscaler gerenciar Auto Scaling Groups do EKS"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "autoscaling:DescribeAutoScalingGroups",
          "autoscaling:DescribeAutoScalingInstances",
          "autoscaling:DescribeLaunchConfigurations",
          "autoscaling:DescribeScalingActivities",
          "autoscaling:DescribeTags",
          "ec2:DescribeImages",
          "ec2:DescribeInstanceTypes",
          "ec2:DescribeLaunchTemplateVersions",
          "ec2:GetInstanceTypesFromInstanceRequirements",
          "eks:DescribeNodegroup"
        ]
        Resource = ["*"]
      },
      {
        Effect = "Allow"
        Action = [
          "autoscaling:SetDesiredCapacity",
          "autoscaling:TerminateInstanceInAutoScalingGroup"
        ]
        Resource = ["*"]
        Condition = {
          StringEquals = {
            "autoscaling:ResourceTag/k8s.io/cluster-autoscaler/enabled" : "true",
            "autoscaling:ResourceTag/kubernetes.io/cluster/${var.project_name}-${var.environment}-eks" : "owned"
          }
        }
      }
    ]
  })

  tags = var.tags
}
