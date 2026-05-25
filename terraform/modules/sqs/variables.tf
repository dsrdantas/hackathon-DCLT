variable "project_name"                  { type = string }
variable "environment"                    { type = string }
variable "queue_name"                     { type = string }
variable "eks_node_role_arn"              { type = string }
variable "message_retention_seconds"      { type = number }
variable "visibility_timeout_seconds"     { type = number }
