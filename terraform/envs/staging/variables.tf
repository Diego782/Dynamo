variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Nombre del proyecto"
  type        = string
  default     = "dynamo-dax-demo"
}

variable "owner" {
  description = "Owner del proyecto"
  type        = string
  default     = "DevOps-Team"
}

variable "vpc_cidr" {
  description = "CIDR block para la VPC"
  type        = string
  default     = "10.1.0.0/16"  # Diferente de dev
}

variable "availability_zones" {
  description = "Lista de availability zones"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}
