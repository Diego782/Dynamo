variable "name_prefix" {
  description = "Prefijo para nombrar recursos IAM"
  type        = string
}

variable "dynamodb_table_arns" {
  description = "Lista de ARNs de tablas DynamoDB"
  type        = list(string)
}

variable "lambda_in_vpc" {
  description = "Si true, Lambda está en VPC (necesita VPC access policy)"
  type        = bool
  default     = false
}

variable "enable_secrets_access" {
  description = "Si true, otorga acceso a Secrets Manager"
  type        = bool
  default     = false
}

variable "secrets_arns" {
  description = "Lista de ARNs de secretos en Secrets Manager"
  type        = list(string)
  default     = []
}

variable "kms_key_arns" {
  description = "Lista de ARNs de KMS keys para desencriptar secretos"
  type        = list(string)
  default     = []
}

variable "create_ec2_role" {
  description = "Si true, crea role para instancias EC2/ECS"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags para los recursos IAM"
  type        = map(string)
  default     = {}
}
