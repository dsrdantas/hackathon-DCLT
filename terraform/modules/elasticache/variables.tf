variable "project_name"    { type = string }
variable "environment"      { type = string }
variable "vpc_id"           { type = string }
variable "subnet_ids"       { type = list(string) }
variable "eks_sg_id"        { type = string }
variable "node_type"        { type = string }
variable "engine_version"   { type = string }
variable "num_cache_nodes"  { type = number }
