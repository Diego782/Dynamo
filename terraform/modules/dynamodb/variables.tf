variable "table_name" {
  description = "Nombre de la tabla DynamoDB"
  type        = string
}

variable "billing_mode" {
  description = "Billing mode: PROVISIONED o PAY_PER_REQUEST"
  type        = string
  default     = "PAY_PER_REQUEST"

  validation {
    condition     = contains(["PROVISIONED", "PAY_PER_REQUEST"], var.billing_mode)
    error_message = "billing_mode debe ser PROVISIONED o PAY_PER_REQUEST."
  }
}

variable "table_class" {
  description = "Clase de tabla: STANDARD o STANDARD_INFREQUENT_ACCESS"
  type        = string
  default     = "STANDARD"

  validation {
    condition     = contains(["STANDARD", "STANDARD_INFREQUENT_ACCESS"], var.table_class)
    error_message = "table_class debe ser STANDARD o STANDARD_INFREQUENT_ACCESS."
  }
}

variable "hash_key" {
  description = "Partition key de la tabla"
  type        = string
}

variable "hash_key_type" {
  description = "Tipo del hash key: S (string), N (number), o B (binary)"
  type        = string
  default     = "S"

  validation {
    condition     = contains(["S", "N", "B"], var.hash_key_type)
    error_message = "hash_key_type debe ser S, N, o B."
  }
}

variable "range_key" {
  description = "Sort key de la tabla (opcional)"
  type        = string
  default     = null
}

variable "range_key_type" {
  description = "Tipo del range key"
  type        = string
  default     = "S"

  validation {
    condition     = contains(["S", "N", "B"], var.range_key_type)
    error_message = "range_key_type debe ser S, N, o B."
  }
}

variable "read_capacity" {
  description = "Read capacity units (solo para provisioned mode)"
  type        = number
  default     = 5
}

variable "write_capacity" {
  description = "Write capacity units (solo para provisioned mode)"
  type        = number
  default     = 5
}

variable "global_secondary_indexes" {
  description = "Lista de GSIs"
  type = list(object({
    name               = string
    hash_key           = string
    hash_key_type      = string
    range_key          = optional(string)
    projection_type    = string
    non_key_attributes = optional(list(string))
    read_capacity      = optional(number)
    write_capacity     = optional(number)
  }))
  default = []
}

variable "ttl_enabled" {
  description = "Si true, habilita TTL"
  type        = bool
  default     = false
}

variable "ttl_attribute_name" {
  description = "Nombre del atributo TTL"
  type        = string
  default     = "ttl"
}

variable "point_in_time_recovery_enabled" {
  description = "Si true, habilita PITR"
  type        = bool
  default     = true
}

variable "kms_key_arn" {
  description = "ARN de la KMS key para encriptación (null usa AWS managed key)"
  type        = string
  default     = null
}

variable "stream_enabled" {
  description = "Si true, habilita DynamoDB Streams"
  type        = bool
  default     = false
}

variable "stream_view_type" {
  description = "Tipo de stream view: KEYS_ONLY, NEW_IMAGE, OLD_IMAGE, NEW_AND_OLD_IMAGES"
  type        = string
  default     = "NEW_AND_OLD_IMAGES"

  validation {
    condition = contains([
      "KEYS_ONLY",
      "NEW_IMAGE",
      "OLD_IMAGE",
      "NEW_AND_OLD_IMAGES"
    ], var.stream_view_type)
    error_message = "stream_view_type inválido."
  }
}

variable "enable_autoscaling" {
  description = "Si true, habilita auto-scaling (solo provisioned mode)"
  type        = bool
  default     = false
}

variable "autoscaling_read_target" {
  description = "Target de utilización para read auto-scaling (70%)"
  type        = number
  default     = 70
}

variable "autoscaling_read_max_capacity" {
  description = "Capacidad máxima de lectura para auto-scaling"
  type        = number
  default     = 100
}

variable "autoscaling_write_target" {
  description = "Target de utilización para write auto-scaling (70%)"
  type        = number
  default     = 70
}

variable "autoscaling_write_max_capacity" {
  description = "Capacidad máxima de escritura para auto-scaling"
  type        = number
  default     = 100
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
