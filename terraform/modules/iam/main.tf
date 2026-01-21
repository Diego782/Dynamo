# ============================================================================
# IAM MODULE
# ============================================================================
# Crea roles y policies siguiendo el principio de menor privilegio
# 
# ROLES CREADOS:
# 1. DAX Service Role - Para que DAX acceda a DynamoDB
# 2. Lambda Execution Role - Para que Lambda acceda a DynamoDB y DAX
# 
# PRINCIPIO DE SEGURIDAD: Least Privilege
# ========================================
# ❌ MAL: "Effect": "Allow", "Action": "*", "Resource": "*"
# ✅ BIEN: Permisos específicos, recursos específicos, conditions cuando aplique
# ============================================================================

# ============================================================================
# DAX SERVICE ROLE
# ============================================================================
# Permite a DAX leer/escribir en DynamoDB

resource "aws_iam_role" "dax_service" {
  name               = "${var.name_prefix}-dax-service-role"
  assume_role_policy = data.aws_iam_policy_document.dax_assume_role.json

  tags = merge(
    var.tags,
    {
      Name = "${var.name_prefix}-dax-service-role"
    }
  )
}

data "aws_iam_policy_document" "dax_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["dax.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

# Policy para acceso a DynamoDB
resource "aws_iam_role_policy" "dax_dynamodb_access" {
  name   = "${var.name_prefix}-dax-dynamodb-policy"
  role   = aws_iam_role.dax_service.id
  policy = data.aws_iam_policy_document.dax_dynamodb_access.json
}

data "aws_iam_policy_document" "dax_dynamodb_access" {
  # DAX necesita estos permisos en DynamoDB
  statement {
    effect = "Allow"

    actions = [
      "dynamodb:DescribeTable",
      "dynamodb:PutItem",
      "dynamodb:GetItem",
      "dynamodb:DeleteItem",
      "dynamodb:UpdateItem",
      "dynamodb:Query",
      "dynamodb:Scan",
      "dynamodb:BatchGetItem",
      "dynamodb:BatchWriteItem",
      "dynamodb:ConditionCheckItem"
    ]

    # Limitar a tablas específicas
    resources = var.dynamodb_table_arns
  }

  # DAX también necesita acceso a los índices
  statement {
    effect = "Allow"

    actions = [
      "dynamodb:Query",
      "dynamodb:Scan"
    ]

    resources = [
      for arn in var.dynamodb_table_arns : "${arn}/index/*"
    ]
  }
}

# ============================================================================
# LAMBDA EXECUTION ROLE
# ============================================================================
# Permite a Lambda:
# 1. Escribir logs a CloudWatch
# 2. Acceder a DynamoDB (writes)
# 3. Acceder a DAX (reads)
# 4. Acceder a VPC (ENIs)
# 5. Leer secretos (si aplica)

resource "aws_iam_role" "lambda_execution" {
  name               = "${var.name_prefix}-lambda-execution-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json

  tags = merge(
    var.tags,
    {
      Name = "${var.name_prefix}-lambda-execution-role"
    }
  )
}

data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

# 1. CloudWatch Logs (Básico Lambda)
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# 2. VPC Access (Si Lambda está en VPC para acceder a DAX)
resource "aws_iam_role_policy_attachment" "lambda_vpc_execution" {
  count = var.lambda_in_vpc ? 1 : 0

  role       = aws_iam_role.lambda_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# 3. DynamoDB Access (Writes directos, no vía DAX)
resource "aws_iam_role_policy" "lambda_dynamodb_access" {
  name   = "${var.name_prefix}-lambda-dynamodb-policy"
  role   = aws_iam_role.lambda_execution.id
  policy = data.aws_iam_policy_document.lambda_dynamodb_access.json
}

data "aws_iam_policy_document" "lambda_dynamodb_access" {
  statement {
    effect = "Allow"

    # WRITES: Van directo a DynamoDB (no DAX)
    # READS: Van a DAX (que cacheará y forwarded a DynamoDB si miss)
    actions = [
      "dynamodb:PutItem",
      "dynamodb:UpdateItem",
      "dynamodb:DeleteItem",
      "dynamodb:GetItem",
      "dynamodb:Query",
      "dynamodb:Scan",
      "dynamodb:BatchGetItem",
      "dynamodb:BatchWriteItem"
    ]

    resources = var.dynamodb_table_arns
  }
}

# 4. DAX Access (Reads)
# IMPORTANTE: DAX no tiene IAM policies específicas en el control plane,
# pero sí necesita acceso de red (security groups) y las mismas policies
# de DynamoDB porque DAX asume el rol de la aplicación para acceder a DynamoDB
#
# Por lo tanto, los permisos de DynamoDB arriba son suficientes.

# 5. Secrets Manager Access (Opcional)
resource "aws_iam_role_policy" "lambda_secrets_access" {
  count = var.enable_secrets_access ? 1 : 0

  name   = "${var.name_prefix}-lambda-secrets-policy"
  role   = aws_iam_role.lambda_execution.id
  policy = data.aws_iam_policy_document.lambda_secrets_access[0].json
}

data "aws_iam_policy_document" "lambda_secrets_access" {
  count = var.enable_secrets_access ? 1 : 0

  statement {
    effect = "Allow"

    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret"
    ]

    # Limitar a secretos específicos (mejor práctica)
    resources = var.secrets_arns
  }

  # Si usas KMS para encriptar secretos
  dynamic "statement" {
    for_each = length(var.kms_key_arns) > 0 ? [1] : []
    content {
      effect = "Allow"

      actions = [
        "kms:Decrypt",
        "kms:DescribeKey"
      ]

      resources = var.kms_key_arns
    }
  }
}

# ============================================================================
# EC2/ECS INSTANCE ROLE (Opcional - si no usas Lambda)
# ============================================================================
# Para aplicaciones en EC2 o ECS que necesiten acceder a DynamoDB/DAX

resource "aws_iam_role" "ec2_instance" {
  count = var.create_ec2_role ? 1 : 0

  name               = "${var.name_prefix}-ec2-instance-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role[0].json

  tags = merge(
    var.tags,
    {
      Name = "${var.name_prefix}-ec2-instance-role"
    }
  )
}

data "aws_iam_policy_document" "ec2_assume_role" {
  count = var.create_ec2_role ? 1 : 0

  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_instance_profile" "ec2_instance" {
  count = var.create_ec2_role ? 1 : 0

  name = "${var.name_prefix}-ec2-instance-profile"
  role = aws_iam_role.ec2_instance[0].name

  tags = var.tags
}

resource "aws_iam_role_policy" "ec2_dynamodb_access" {
  count = var.create_ec2_role ? 1 : 0

  name   = "${var.name_prefix}-ec2-dynamodb-policy"
  role   = aws_iam_role.ec2_instance[0].id
  policy = data.aws_iam_policy_document.lambda_dynamodb_access.json
}

# ============================================================================
# ¿QUÉ DIRÍA UN SENIOR EN UNA ENTREVISTA?
# ============================================================================
# "Seguimos el principio de menor privilegio. Cada rol tiene exactamente
# los permisos necesarios, nada más. Los recursos están explícitamente
# limitados (no usamos '*').
#
# Para DAX, el rol de servicio necesita acceso completo a DynamoDB porque
# DAX actúa como proxy. Para Lambda, separamos conceptualmente los writes
# (directo a DynamoDB) de los reads (vía DAX), aunque ambos usan las
# mismas policies IAM.
#
# En producción, añadiríamos:
# 1. Conditions en las policies (e.g., IpAddress, SecureTransport)
# 2. Permission boundaries para prevenir escalación de privilegios
# 3. SCPs a nivel de organización
# 4. Monitoreo con CloudTrail e IAM Access Analyzer
# 5. Rotación automática de credenciales
#
# Para debugging, usaría IAM Policy Simulator y CloudTrail para validar
# que los permisos son correctos y no hay accesos no autorizados."
# ============================================================================
