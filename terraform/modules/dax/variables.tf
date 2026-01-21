variable "cluster_name" {
  description = "Nombre del cluster DAX"
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9-]*$", var.cluster_name))
    error_message = "cluster_name debe comenzar con letra y solo contener letras, números y guiones."
  }
}

variable "node_type" {
  description = "Tipo de nodo DAX (e.g., dax.t3.small, dax.r5.large)"
  type        = string
  default     = "dax.t3.small"

  validation {
    condition = can(regex("^dax\\.(t[0-9]|r[0-9]|r[0-9]e)\\.(small|medium|large|xlarge|[0-9]+xlarge)$", var.node_type))
    error_message = "node_type debe ser un tipo DAX válido."
  }
}

variable "replication_factor" {
  description = "Número de nodos en el cluster (1-10)"
  type        = number
  default     = 1

  validation {
    condition     = var.replication_factor >= 1 && var.replication_factor <= 10
    error_message = "replication_factor debe estar entre 1 y 10."
  }
}

variable "iam_role_arn" {
  description = "ARN del IAM role para DAX"
  type        = string
}

variable "subnet_ids" {
  description = "Lista de subnet IDs para el cluster DAX (privadas)"
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 1
    error_message = "Debe proporcionar al menos una subnet."
  }
}

variable "vpc_id" {
  description = "ID de la VPC"
  type        = string
}

variable "allowed_security_group_ids" {
  description = "Lista de security group IDs que pueden acceder a DAX"
  type        = list(string)
  default     = []
}

variable "item_cache_ttl_seconds" {
  description = "TTL del cache para items individuales (segundos)"
  type        = number
  default     = 300  # 5 minutos

  validation {
    condition     = var.item_cache_ttl_seconds >= 0 && var.item_cache_ttl_seconds <= 86400
    error_message = "item_cache_ttl_seconds debe estar entre 0 y 86400 (24 horas)."
  }
}

variable "query_cache_ttl_seconds" {
  description = "TTL del cache para queries (segundos)"
  type        = number
  default     = 300  # 5 minutos

  validation {
    condition     = var.query_cache_ttl_seconds >= 0 && var.query_cache_ttl_seconds <= 86400
    error_message = "query_cache_ttl_seconds debe estar entre 0 y 86400."
  }
}

variable "encryption_type" {
  description = "Tipo de encriptación: NONE o TLS"
  type        = string
  default     = "TLS"

  validation {
    condition     = contains(["NONE", "TLS"], var.encryption_type)
    error_message = "encryption_type debe ser NONE o TLS."
  }
}

variable "maintenance_window" {
  description = "Ventana de mantenimiento (UTC, formato: ddd:hh24:mi-ddd:hh24:mi)"
  type        = string
  default     = "sun:05:00-sun:06:00"
}

variable "notification_topic_arn" {
  description = "ARN del SNS topic para notificaciones (opcional)"
  type        = string
  default     = null
}

variable "availability_zones" {
  description = "Lista de AZs para distribuir nodos (opcional, AWS lo hace automáticamente si se omite)"
  type        = list(string)
  default     = []
}

variable "enable_alarms" {
  description = "Si true, crea CloudWatch alarms"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags para los recursos"
  type        = map(string)
  default     = {}
}
