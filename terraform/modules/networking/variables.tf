variable "name_prefix" {
  description = "Prefijo para nombrar recursos"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block para la VPC"
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr debe ser un CIDR block válido."
  }
}

variable "availability_zones" {
  description = "Lista de availability zones"
  type        = list(string)
}

variable "region" {
  description = "AWS region"
  type        = string
}

variable "single_nat_gateway" {
  description = "Si true, usa solo una NAT gateway (más barato, menos disponible)"
  type        = bool
  default     = false
}

variable "enable_dynamodb_endpoint" {
  description = "Si true, crea VPC endpoint para DynamoDB (recomendado)"
  type        = bool
  default     = true
}

variable "enable_flow_logs" {
  description = "Si true, habilita VPC Flow Logs"
  type        = bool
  default     = false
}

variable "flow_logs_retention_days" {
  description = "Días de retención de Flow Logs"
  type        = number
  default     = 7
}

variable "tags" {
  description = "Tags comunes para todos los recursos"
  type        = map(string)
  default     = {}
}
