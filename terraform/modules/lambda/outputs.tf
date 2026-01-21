output "function_name" {
  description = "Nombre de la función Lambda"
  value       = aws_lambda_function.main.function_name
}

output "function_arn" {
  description = "ARN de la función Lambda"
  value       = aws_lambda_function.main.arn
}

output "invoke_arn" {
  description = "Invoke ARN para API Gateway"
  value       = aws_lambda_function.main.invoke_arn
}

output "log_group_name" {
  description = "Nombre del CloudWatch Log Group"
  value       = aws_cloudwatch_log_group.lambda_logs.name
}
