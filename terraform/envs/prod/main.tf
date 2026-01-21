# ============================================================================
# PRODUCTION ENVIRONMENT
# ============================================================================
# Configuración production-grade
# - Recursos optimizados para producción
# - Múltiples NAT Gateways (HA)
# - DAX cluster con 3+ nodos
# - PITR, alarmas, flow logs habilitados
# - Provisioned billing (si tráfico es predecible)
# ============================================================================

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Backend remoto
  # backend "s3" {
  #   bucket         = "dynamo-demo-tfstate-bootstrap"
  #   key            = "envs/prod/terraform.tfstate"
  #   region         = "us-east-1"
  #   dynamodb_table = "dynamo-demo-tfstate-lock"
  #   encrypt        = true
  # }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = "DynamoDAX-Demo"
      Environment = "prod"
      ManagedBy   = "Terraform"
      Owner       = var.owner
      CostCenter  = "Engineering"
      Compliance  = "PCI-DSS"  # Ejemplo
    }
  }
}

locals {
  name_prefix = "${var.project_name}-prod"
  
  common_tags = {
    Environment = "prod"
    Project     = var.project_name
  }
}

# ============================================================================
# NETWORKING MODULE
# ============================================================================

module "networking" {
  source = "../../modules/networking"

  name_prefix        = local.name_prefix
  vpc_cidr           = var.vpc_cidr
  availability_zones = var.availability_zones
  region             = var.region

  # PROD: NAT por AZ (alta disponibilidad)
  single_nat_gateway = false

  enable_dynamodb_endpoint = true
  
  # Flow logs habilitados (compliance/security)
  enable_flow_logs         = true
  flow_logs_retention_days = 90  # 90 días para auditoría

  tags = local.common_tags
}

# ============================================================================
# IAM MODULE
# ============================================================================

module "iam" {
  source = "../../modules/iam"

  name_prefix         = local.name_prefix
  dynamodb_table_arns = [module.dynamodb.table_arn]
  lambda_in_vpc       = true
  
  enable_secrets_access = false
  create_ec2_role       = false

  tags = local.common_tags
}

# ============================================================================
# DYNAMODB MODULE
# ============================================================================

module "dynamodb" {
  source = "../../modules/dynamodb"

  table_name   = "${local.name_prefix}-products"
  
  # DECISIÓN: On-Demand vs Provisioned
  # Si el tráfico es predecible y constante, cambiar a PROVISIONED
  # con auto-scaling para optimizar costos
  billing_mode = "PAY_PER_REQUEST"  # Cambiar a "PROVISIONED" si aplica
  table_class  = "STANDARD"

  hash_key       = "ProductID"
  hash_key_type  = "S"
  range_key      = "Version"
  range_key_type = "N"

  global_secondary_indexes = [
    {
      name            = "CategoryIndex"
      hash_key        = "Category"
      hash_key_type   = "S"
      range_key       = null
      projection_type = "ALL"
    }
  ]

  ttl_enabled                    = true
  ttl_attribute_name             = "ExpiresAt"
  point_in_time_recovery_enabled = true
  
  # PROD: Usar CMK para encriptación (no implementado aquí, pero recomendado)
  kms_key_arn = null  # TODO: Crear KMS key en producción

  # PROD: Stream habilitado para replication/analytics
  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"

  enable_autoscaling = false  # Solo si billing_mode = PROVISIONED
  
  # PROD: Alarmas críticas
  enable_alarms = true

  tags = local.common_tags
}

# ============================================================================
# DAX MODULE
# ============================================================================

module "dax" {
  source = "../../modules/dax"

  cluster_name       = "${local.name_prefix}-dax"
  node_type          = "dax.r5.large"   # Nodo production-grade
  replication_factor = 3                 # 3 nodos para HA

  iam_role_arn = module.iam.dax_service_role_arn
  subnet_ids   = module.networking.private_subnet_ids
  vpc_id       = module.networking.vpc_id

  allowed_security_group_ids = [aws_security_group.lambda.id]

  # Cache TTL: Ajustar según caso de uso
  item_cache_ttl_seconds  = 600   # 10 minutos
  query_cache_ttl_seconds = 300   # 5 minutos

  encryption_type    = "TLS"
  maintenance_window = "sun:05:00-sun:06:00"

  # PROD: Alarmas críticas
  enable_alarms = true

  tags = local.common_tags

  depends_on = [module.iam]
}

# ============================================================================
# LAMBDA SECURITY GROUP
# ============================================================================

resource "aws_security_group" "lambda" {
  name_prefix = "${local.name_prefix}-lambda-"
  description = "Security group for Lambda functions"
  vpc_id      = module.networking.vpc_id

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-lambda-sg"
    }
  )

  lifecycle {
    create_before_destroy = true
  }
}

# ============================================================================
# OUTPUTS
# ============================================================================

output "vpc_id" {
  value = module.networking.vpc_id
}

output "dynamodb_table_name" {
  value = module.dynamodb.table_name
}

output "dax_cluster_endpoint" {
  value = module.dax.cluster_address
}

output "lambda_execution_role_arn" {
  value = module.iam.lambda_execution_role_arn
}

output "lambda_security_group_id" {
  value = aws_security_group.lambda.id
}

output "lambda_subnet_ids" {
  value = module.networking.private_subnet_ids
}
