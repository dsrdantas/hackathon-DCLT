variable "project_name"      { type = string }
variable "environment"        { type = string }
variable "service_name"       { type = string; description = "Identificador do serviço: 'ngo' ou 'donation'" }
variable "vpc_id"             { type = string }
variable "subnet_ids"         { type = list(string) }
variable "eks_sg_id"          { type = string }
variable "instance_class"     { type = string }
variable "engine_version"     { type = string }
variable "db_name"            { type = string }
variable "username"           { type = string }
variable "password"           { type = string; sensitive = true }
variable "allocated_storage"  { type = number }
variable "multi_az"           { type = bool }
