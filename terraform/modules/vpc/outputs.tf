output "vpc_id" { value = aws_vpc.this.id }
output "public_subnet_ids" { value = aws_subnet.public[*].id }
output "eks_subnet_ids" { value = aws_subnet.eks[*].id }
output "rds_subnet_ids" { value = aws_subnet.rds[*].id }
output "elasticache_subnet_ids" { value = aws_subnet.elasticache[*].id }
output "private_route_table_id" { value = aws_route_table.private.id }
output "public_route_table_id" { value = aws_route_table.public.id }
output "vpce_sg_id" {
  description = "Security Group das ENIs dos Interface Endpoints"
  value       = aws_security_group.vpce.id
}
