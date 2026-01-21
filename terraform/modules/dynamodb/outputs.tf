output "table_name" {
  description = "Nombre de la tabla DynamoDB"
  value       = aws_dynamodb_table.main.name
}

output "table_arn" {
  description = "ARN de la tabla DynamoDB"
  value       = aws_dynamodb_table.main.arn
}

output "table_id" {
  description = "ID de la tabla DynamoDB"
  value       = aws_dynamodb_table.main.id
}

output "stream_arn" {
  description = "ARN del stream de DynamoDB (si está habilitado)"
  value       = var.stream_enabled ? aws_dynamodb_table.main.stream_arn : null
}

output "stream_label" {
  description = "Label del stream de DynamoDB"
  value       = var.stream_enabled ? aws_dynamodb_table.main.stream_label : null
}

output "hash_key" {
  description = "Partition key de la tabla"
  value       = var.hash_key
}

output "range_key" {
  description = "Sort key de la tabla"
  value       = var.range_key
}
