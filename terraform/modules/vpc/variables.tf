variable "project_name"             { type = string }
variable "environment"               { type = string }
variable "vpc_cidr"                  { type = string }
variable "availability_zones"        { type = list(string) }
variable "public_subnet_cidrs"       { type = list(string) }
variable "eks_subnet_cidrs"          { type = list(string) }
variable "rds_subnet_cidrs"          { type = list(string); description = "Subnets privadas compartilhadas pelos bancos RDS (uma por AZ)" }
variable "elasticache_subnet_cidrs"  { type = list(string) }
