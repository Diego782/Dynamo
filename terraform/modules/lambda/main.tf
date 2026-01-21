# ============================================================================
# LAMBDA MODULE
# ============================================================================
# Crea Lambda function con todas las configuraciones necesarias
# ============================================================================

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = var.source_dir
  output_path = "${path.module}/../../.build/${var.function_name}.zip"
}

resource "aws_lambda_function" "main" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = var.function_name
  role             = var.role_arn
  handler          = var.handler
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  runtime          = var.runtime
  timeout          = var.timeout
  memory_size      = var.memory_size

  environment {
    variables = merge(
      {
        TABLE_NAME   = var.table_name
        DAX_ENDPOINT = var.dax_endpoint
        AWS_REGION   = var.region
      },
      var.environment_variables
    )
  }

  # Si Lambda está en VPC (para acceder a DAX)
  dynamic "vpc_config" {
    for_each = var.subnet_ids != null ? [1] : []
    content {
      subnet_ids         = var.subnet_ids
      security_group_ids = var.security_group_ids
    }
  }

  # Tracing con X-Ray (opcional)
  tracing_config {
    mode = var.enable_xray ? "Active" : "PassThrough"
  }

  # Reserved concurrent executions (opcional)
  reserved_concurrent_executions = var.reserved_concurrent_executions

  tags = merge(
    var.tags,
    {
      Name = var.function_name
    }
  )
}

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${var.function_name}"
  retention_in_days = var.log_retention_days

  tags = var.tags
}

# Lambda permission para API Gateway
resource "aws_lambda_permission" "api_gateway" {
  count = var.api_gateway_arn != null ? 1 : 0

  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.main.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${var.api_gateway_arn}/*/*"
}
