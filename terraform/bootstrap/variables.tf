variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "state_bucket_name" {
  description = "Nombre del bucket S3 para el Terraform state"
  type        = string
  default     = "dynamo-demo-tfstate-bootstrap"
  
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]*[a-z0-9]$", var.state_bucket_name))
    error_message = "El nombre del bucket debe ser DNS-compliant (lowercase, números, guiones)."
  }
}

variable "dynamodb_table_name" {
  description = "Nombre de la tabla DynamoDB para state locking"
  type        = string
  default     = "dynamo-demo-tfstate-lock"
}
