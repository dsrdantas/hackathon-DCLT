output "cluster_name" { value = aws_eks_cluster.this.name }
output "cluster_endpoint" { value = aws_eks_cluster.this.endpoint }
output "cluster_ca" { value = aws_eks_cluster.this.certificate_authority[0].data }
output "node_security_group_id" { value = aws_security_group.nodes.id }
output "cluster_security_group_id" { value = aws_security_group.cluster.id }
output "node_role_arn" { value = data.aws_iam_role.lab_role.arn }
