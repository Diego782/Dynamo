# ============================================================================
# STAGING ENVIRONMENT
# ============================================================================
# Configuración para staging (pre-producción)
# - Recursos medianos
# - Múltiples NAT Gateways (alta disponibilidad)
# - DAX cluster con 2 nodos
# - Alarmas habilitadas
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
  #   key            = "envs/staging/terraform.tfstate"
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
      Environment = "staging"
      ManagedBy   = "Terraform"
      Owner       = var.owner
      CostCenter  = "Engineering"
    }
  }
}

locals {
  name_prefix = "${var.project_name}-staging"
  
  common_tags = {
    Environment = "staging"
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

  # STAGING: NAT por AZ para alta disponibilidad
  single_nat_gateway = false

  enable_dynamodb_endpoint = true
  enable_flow_logs         = true
  flow_logs_retention_days = 30

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
  billing_mode = "PAY_PER_REQUEST"
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
  kms_key_arn                    = null

  stream_enabled   = false
  enable_autoscaling = false
  
  # STAGING: Alarmas habilitadas
  enable_alarms = true

  tags = local.common_tags
}

# ============================================================================
# DAX MODULE
# ============================================================================

module "dax" {
  source = "../../modules/dax"

  cluster_name       = "${local.name_prefix}-dax"
  node_type          = "dax.t3.medium"  # Nodo mediano
  replication_factor = 2                 # 2 nodos para HA

  iam_role_arn = module.iam.dax_service_role_arn
  subnet_ids   = module.networking.private_subnet_ids
  vpc_id       = module.networking.vpc_id

  allowed_security_group_ids = [aws_security_group.lambda.id]

  item_cache_ttl_seconds  = 300
  query_cache_ttl_seconds = 300
  encryption_type         = "TLS"
  maintenance_window      = "sun:05:00-sun:06:00"

  # STAGING: Alarmas habilitadas
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
