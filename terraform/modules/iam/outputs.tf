output "dax_service_role_arn" {
  description = "ARN del rol de servicio para DAX"
  value       = aws_iam_role.dax_service.arn
}

output "dax_service_role_name" {
  description = "Nombre del rol de servicio para DAX"
  value       = aws_iam_role.dax_service.name
}

output "lambda_execution_role_arn" {
  description = "ARN del rol de ejecución para Lambda"
  value       = aws_iam_role.lambda_execution.arn
}

output "lambda_execution_role_name" {
  description = "Nombre del rol de ejecución para Lambda"
  value       = aws_iam_role.lambda_execution.name
}

output "ec2_instance_role_arn" {
  description = "ARN del rol de instancia EC2 (si fue creado)"
  value       = var.create_ec2_role ? aws_iam_role.ec2_instance[0].arn : null
}

output "ec2_instance_profile_name" {
  description = "Nombre del instance profile para EC2 (si fue creado)"
  value       = var.create_ec2_role ? aws_iam_instance_profile.ec2_instance[0].name : null
}
