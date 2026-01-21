variable "function_name" {
  description = "Nombre de la función Lambda"
  type        = string
}

variable "handler" {
  description = "Handler de la función"
  type        = string
  default     = "index.handler"
}

variable "runtime" {
  description = "Runtime de Lambda"
  type        = string
  default     = "nodejs18.x"
}

variable "timeout" {
  description = "Timeout en segundos"
  type        = number
  default     = 30
}

variable "memory_size" {
  description = "Memoria en MB"
  type        = number
  default     = 256
}

variable "role_arn" {
  description = "ARN del IAM role"
  type        = string
}

variable "source_dir" {
  description = "Directorio con el código fuente"
  type        = string
}

variable "table_name" {
  description = "Nombre de la tabla DynamoDB"
  type        = string
}

variable "dax_endpoint" {
  description = "Endpoint del cluster DAX"
  type        = string
}

variable "region" {
  description = "AWS region"
  type        = string
}

variable "environment_variables" {
  description = "Variables de entorno adicionales"
  type        = map(string)
  default     = {}
}

variable "subnet_ids" {
  description = "IDs de subnets para VPC config"
  type        = list(string)
  default     = null
}

variable "security_group_ids" {
  description = "IDs de security groups"
  type        = list(string)
  default     = null
}

variable "enable_xray" {
  description = "Habilitar X-Ray tracing"
  type        = bool
  default     = false
}

variable "reserved_concurrent_executions" {
  description = "Concurrent executions reservadas (-1 = sin límite)"
  type        = number
  default     = -1
}

variable "log_retention_days" {
  description = "Días de retención de logs"
  type        = number
  default     = 7
}

variable "api_gateway_arn" {
  description = "ARN del API Gateway (para permissions)"
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags"
  type        = map(string)
  default     = {}
}
