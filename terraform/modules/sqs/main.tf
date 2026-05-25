locals {
  name_prefix = "${var.project_name}-${var.environment}"
  queue_name  = "${local.name_prefix}-${var.queue_name}"
  dlq_name    = "${local.name_prefix}-${var.queue_name}-dlq"
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ── Dead Letter Queue ─────────────────────────────────────────
resource "aws_sqs_queue" "dlq" {
  name                       = local.dlq_name
  message_retention_seconds  = 1209600   # 14 dias (máximo)
  kms_master_key_id          = "alias/aws/sqs"

  tags = { Name = local.dlq_name }
}

# ── Fila principal ────────────────────────────────────────────
resource "aws_sqs_queue" "this" {
  name                       = local.queue_name
  message_retention_seconds  = var.message_retention_seconds
  visibility_timeout_seconds = var.visibility_timeout_seconds
  kms_master_key_id          = "alias/aws/sqs"

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = 5
  })

  tags = { Name = local.queue_name, Tier = "messaging", Service = "sqs-donations" }
}

# ── Queue Policy — acesso pelos nós EKS ──────────────────────
resource "aws_sqs_queue_policy" "this" {
  queue_url = aws_sqs_queue.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowEKSNodes"
        Effect = "Allow"
        Principal = {
          AWS = var.eks_node_role_arn
        }
        Action = [
          "sqs:SendMessage",
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes",
          "sqs:GetQueueUrl"
        ]
        Resource = aws_sqs_queue.this.arn
      }
    ]
  })
}
