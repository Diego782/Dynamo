# ============================================================================
# DEV ENVIRONMENT
# ============================================================================
# Configuración optimizada para desarrollo y testing
# - Recursos mínimos (costo bajo)
# - Una sola NAT Gateway
# - DAX cluster pequeño (1 nodo)
# - Sin alarmas (para evitar ruido)
# ============================================================================

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Backend remoto (descomentar después del bootstrap)
  # backend "s3" {
  #   bucket         = "dynamo-demo-tfstate-bootstrap"
  #   key            = "envs/dev/terraform.tfstate"
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
      Environment = "dev"
      ManagedBy   = "Terraform"
      Owner       = var.owner
      CostCenter  = "Engineering"
    }
  }
}

# ============================================================================
# LOCALS
# ============================================================================

locals {
  name_prefix = "${var.project_name}-dev"
  
  common_tags = {
    Environment = "dev"
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

  # DEV: Una sola NAT gateway para ahorrar costos (~$32/mes vs ~$96/mes)
  single_nat_gateway = true

  # VPC endpoint para DynamoDB (sin costo adicional, mejor performance)
  enable_dynamodb_endpoint = true

  # Flow logs deshabilitados en dev (habilitar si necesitas troubleshooting)
  enable_flow_logs         = false
  flow_logs_retention_days = 7

  tags = local.common_tags
}

# ============================================================================
# IAM MODULE
# ============================================================================

module "iam" {
  source = "../../modules/iam"

  name_prefix         = local.name_prefix
  dynamodb_table_arns = [module.dynamodb.table_arn]

  # Lambda estará en VPC para acceder a DAX
  lambda_in_vpc = true

  # Secrets access deshabilitado por ahora
  enable_secrets_access = false
  secrets_arns          = []
  kms_key_arns          = []

  # No necesitamos EC2 role en este demo
  create_ec2_role = false

  tags = local.common_tags
}

# ============================================================================
# DYNAMODB MODULE
# ============================================================================

module "dynamodb" {
  source = "../../modules/dynamodb"

  table_name   = "${local.name_prefix}-products"
  billing_mode = "PAY_PER_REQUEST"  # On-demand para dev (sin planificación)
  table_class  = "STANDARD"

  # Schema: Catálogo de productos
  hash_key      = "ProductID"
  hash_key_type = "S"
  range_key     = "Version"
  range_key_type = "N"

  # GSI para buscar por categoría
  global_secondary_indexes = [
    {
      name            = "CategoryIndex"
      hash_key        = "Category"
      hash_key_type   = "S"
      range_key       = null
      projection_type = "ALL"
    }
  ]

  # TTL habilitado para casos de uso con expiración
  ttl_enabled        = true
  ttl_attribute_name = "ExpiresAt"

  # PITR habilitado (backup continuo, recomendado incluso en dev)
  point_in_time_recovery_enabled = true

  # Encriptación con AWS managed key (gratis)
  kms_key_arn = null

  # Stream deshabilitado (habilitar si necesitas triggers/replication)
  stream_enabled   = false
  stream_view_type = "NEW_AND_OLD_IMAGES"

  # Auto-scaling no aplica en on-demand mode
  enable_autoscaling = false

  # Alarmas deshabilitadas en dev
  enable_alarms = false

  tags = local.common_tags
}

# ============================================================================
# DAX MODULE
# ============================================================================

module "dax" {
  source = "../../modules/dax"

  cluster_name       = "${local.name_prefix}-dax"
  node_type          = "dax.t3.small"     # Nodo pequeño para dev
  replication_factor = 1                   # Un solo nodo (no HA)

  iam_role_arn = module.iam.dax_service_role_arn
  subnet_ids   = module.networking.private_subnet_ids
  vpc_id       = module.networking.vpc_id

  # Permitir acceso desde Lambda
  allowed_security_group_ids = [aws_security_group.lambda.id]

  # Cache TTL: 5 minutos (ajustar según necesidad)
  item_cache_ttl_seconds  = 300
  query_cache_ttl_seconds = 300

  # Encriptación TLS habilitada
  encryption_type = "TLS"

  # Ventana de mantenimiento: Domingos 5-6 AM UTC (madrugada en US)
  maintenance_window = "sun:05:00-sun:06:00"

  # Sin notificaciones en dev
  notification_topic_arn = null

  # Dejar que AWS distribuya automáticamente
  availability_zones = []

  # Sin alarmas en dev
  enable_alarms = false

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

  # Egress: Lambda necesita acceso a DAX y DynamoDB
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
# LAMBDA FUNCTION
# ============================================================================

module "lambda_products" {
  source = "../../modules/lambda"

  function_name = "${local.name_prefix}-products-api"
  handler       = "src/handlers/products.handler"
  runtime       = "nodejs18.x"
  timeout       = 30
  memory_size   = 256

  role_arn    = module.iam.lambda_execution_role_arn
  source_dir  = "${path.module}/../../../app"
  table_name  = module.dynamodb.table_name
  dax_endpoint = module.dax.cluster_address
  region      = var.region

  # VPC config para acceder a DAX
  subnet_ids         = module.networking.private_subnet_ids
  security_group_ids = [aws_security_group.lambda.id]

  # X-Ray deshabilitado en dev
  enable_xray = false

  log_retention_days = 7

  api_gateway_arn = aws_apigatewayv2_api.main.execution_arn

  tags = local.common_tags

  depends_on = [
    module.networking,
    module.dax,
    module.iam
  ]
}

# ============================================================================
# API GATEWAY HTTP API
# ============================================================================

resource "aws_apigatewayv2_api" "main" {
  name          = "${local.name_prefix}-api"
  protocol_type = "HTTP"
  description   = "API for DynamoDB/DAX demo"

  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["GET", "POST", "PUT", "DELETE", "OPTIONS"]
    allow_headers = ["*"]
    max_age       = 300
  }

  tags = local.common_tags
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.main.id
  name        = "$default"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gateway.arn
    format = jsonencode({
      requestId      = "$context.requestId"
      ip             = "$context.identity.sourceIp"
      requestTime    = "$context.requestTime"
      httpMethod     = "$context.httpMethod"
      routeKey       = "$context.routeKey"
      status         = "$context.status"
      protocol       = "$context.protocol"
      responseLength = "$context.responseLength"
    })
  }

  tags = local.common_tags
}

resource "aws_cloudwatch_log_group" "api_gateway" {
  name              = "/aws/apigateway/${local.name_prefix}"
  retention_in_days = 7

  tags = local.common_tags
}

# Integration
resource "aws_apigatewayv2_integration" "lambda_products" {
  api_id           = aws_apigatewayv2_api.main.id
  integration_type = "AWS_PROXY"

  connection_type      = "INTERNET"
  description          = "Lambda integration for products API"
  integration_method   = "POST"
  integration_uri      = module.lambda_products.invoke_arn
  payload_format_version = "2.0"
}

# Routes
resource "aws_apigatewayv2_route" "create_product" {
  api_id    = aws_apigatewayv2_api.main.id
  route_key = "POST /products"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_products.id}"
}

resource "aws_apigatewayv2_route" "get_product" {
  api_id    = aws_apigatewayv2_api.main.id
  route_key = "GET /products/{id}"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_products.id}"
}

resource "aws_apigatewayv2_route" "list_products" {
  api_id    = aws_apigatewayv2_api.main.id
  route_key = "GET /products"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_products.id}"
}

resource "aws_apigatewayv2_route" "update_product" {
  api_id    = aws_apigatewayv2_api.main.id
  route_key = "PUT /products/{id}"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_products.id}"
}

resource "aws_apigatewayv2_route" "delete_product" {
  api_id    = aws_apigatewayv2_api.main.id
  route_key = "DELETE /products/{id}"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_products.id}"
}

# ============================================================================
# OUTPUTS
# ============================================================================

output "vpc_id" {
  description = "ID de la VPC"
  value       = module.networking.vpc_id
}

output "dynamodb_table_name" {
  description = "Nombre de la tabla DynamoDB"
  value       = module.dynamodb.table_name
}

output "dax_cluster_endpoint" {
  description = "Endpoint del cluster DAX"
  value       = module.dax.cluster_address
}

output "lambda_function_name" {
  description = "Nombre de la función Lambda"
  value       = module.lambda_products.function_name
}

output "api_gateway_url" {
  description = "URL del API Gateway"
  value       = aws_apigatewayv2_stage.default.invoke_url
}

output "api_gateway_id" {
  description = "ID del API Gateway"
  value       = aws_apigatewayv2_api.main.id
}
