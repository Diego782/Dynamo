output "cluster_name" {
  description = "Nombre del cluster DAX"
  value       = aws_dax_cluster.main.cluster_name
}

output "cluster_arn" {
  description = "ARN del cluster DAX"
  value       = aws_dax_cluster.main.arn
}

output "cluster_address" {
  description = "Endpoint de escritura del cluster DAX"
  value       = aws_dax_cluster.main.cluster_address
}

output "port" {
  description = "Puerto del cluster DAX"
  value       = aws_dax_cluster.main.port
}

output "configuration_endpoint" {
  description = "Endpoint de configuración del cluster (para auto-discovery)"
  value       = aws_dax_cluster.main.configuration_endpoint
}

output "security_group_id" {
  description = "ID del security group del cluster DAX"
  value       = aws_security_group.dax.id
}

output "subnet_group_name" {
  description = "Nombre del subnet group"
  value       = aws_dax_subnet_group.main.name
}

output "parameter_group_name" {
  description = "Nombre del parameter group"
  value       = aws_dax_parameter_group.main.name
}

output "nodes" {
  description = "Información de los nodos del cluster"
  value = [
    for node in aws_dax_cluster.main.nodes : {
      id                = node.id
      address           = node.address
      port              = node.port
      availability_zone = node.availability_zone
    }
  ]
}
