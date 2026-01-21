# ============================================================================
# DYNAMODB MODULE
# ============================================================================
# Crea una tabla DynamoDB optimizada para producción
# 
# CASO DE USO: Catálogo de productos de e-commerce
# - PK: ProductID (UUID)
# - SK: Version (timestamp o número)
# - GSI: CategoryIndex (consultas por categoría)
# 
# DECISIONES DE ARQUITECTURA:
# ===========================
# 
# 1. BILLING MODE: On-Demand vs Provisioned
# ------------------------------------------
# ✅ On-Demand (seleccionado):
#   - PRO: Sin planificación de capacidad
#   - PRO: Auto-scaling automático
#   - PRO: Ideal para cargas impredecibles
#   - CON: Más caro con tráfico constante alto
# 
# ❌ Provisioned:
#   - PRO: Más barato con tráfico predecible
#   - PRO: Control granular con auto-scaling
#   - CON: Requiere tuning y monitoreo
#   - CON: Puede throttle si se excede
# 
# ENTREVISTA: "Elegimos on-demand para dev/staging por simplicidad.
# En producción, con patrones de tráfico estables, evaluaríamos
# provisioned con auto-scaling para optimizar costos."
# 
# 2. TTL (Time To Live)
# ---------------------
# Habilitado para casos como:
# - Sesiones temporales
# - Cache de datos
# - Datos con vencimiento natural
# ============================================================================

resource "aws_dynamodb_table" "main" {
  name         = var.table_name
  billing_mode = var.billing_mode
  hash_key     = var.hash_key
  range_key    = var.range_key

  # Solo para provisioned mode
  read_capacity  = var.billing_mode == "PROVISIONED" ? var.read_capacity : null
  write_capacity = var.billing_mode == "PROVISIONED" ? var.write_capacity : null

  # Clase de tabla (STANDARD vs STANDARD_INFREQUENT_ACCESS)
  table_class = var.table_class

  # ============================================================================
  # ATRIBUTOS
  # ============================================================================
  # Solo se declaran atributos usados en keys (PK, SK, GSI keys)

  attribute {
    name = var.hash_key
    type = var.hash_key_type
  }

  dynamic "attribute" {
    for_each = var.range_key != null ? [1] : []
    content {
      name = var.range_key
      type = var.range_key_type
    }
  }

  # Atributos adicionales para GSIs
  dynamic "attribute" {
    for_each = var.global_secondary_indexes
    content {
      name = attribute.value.hash_key
      type = attribute.value.hash_key_type
    }
  }

  # ============================================================================
  # GLOBAL SECONDARY INDEXES (GSI)
  # ============================================================================
  # Permiten consultas por atributos que no son PK/SK
  # 
  # EJEMPLO: CategoryIndex
  # - Buscar todos los productos de una categoría
  # - Query: CategoryID + opcional Sort por precio/rating
  # 
  # TRADE-OFFS:
  # - Costo: Consumen WCU/RCU adicionales
  # - Eventual consistency: GSI se actualiza asincrónicamente
  # - Límite: 20 GSIs por tabla

  dynamic "global_secondary_index" {
    for_each = var.global_secondary_indexes
    content {
      name            = global_secondary_index.value.name
      hash_key        = global_secondary_index.value.hash_key
      range_key       = lookup(global_secondary_index.value, "range_key", null)
      projection_type = global_secondary_index.value.projection_type
      
      # Atributos proyectados (solo si projection_type = INCLUDE)
      non_key_attributes = lookup(global_secondary_index.value, "non_key_attributes", null)

      # Capacidad (solo para provisioned)
      read_capacity  = var.billing_mode == "PROVISIONED" ? global_secondary_index.value.read_capacity : null
      write_capacity = var.billing_mode == "PROVISIONED" ? global_secondary_index.value.write_capacity : null
    }
  }

  # ============================================================================
  # TTL (Time To Live)
  # ============================================================================
  # Elimina automáticamente items expirados (gratis, procesamiento background)

  dynamic "ttl" {
    for_each = var.ttl_enabled ? [1] : []
    content {
      enabled        = true
      attribute_name = var.ttl_attribute_name
    }
  }

  # ============================================================================
  # POINT-IN-TIME RECOVERY (PITR)
  # ============================================================================
  # Backup continuo (retención: 35 días)
  # Costo: ~$0.20 por GB/mes
  # 
  # ENTREVISTA: "PITR es obligatorio en producción. Permite restaurar
  # a cualquier punto en el tiempo sin downtime. Es complementario a
  # AWS Backup para snapshots programados."

  point_in_time_recovery {
    enabled = var.point_in_time_recovery_enabled
  }

  # ============================================================================
  # SERVER-SIDE ENCRYPTION
  # ============================================================================
  # Opción 1: AWS owned key (default, gratis)
  # Opción 2: AWS managed key (aws/dynamodb, gratis)
  # Opción 3: Customer managed key (CMK, pago por uso) ✅
  # 
  # CMK permite:
  # - Key rotation automática
  # - Control de acceso granular
  # - Audit trail en CloudTrail

  server_side_encryption {
    enabled     = true
    kms_key_arn = var.kms_key_arn
  }

  # ============================================================================
  # STREAM
  # ============================================================================
  # Captura cambios en tiempo real para:
  # - Lambda triggers
  # - Replicación cross-region
  # - Analytics
  # - Audit trails

  dynamic "stream_specification" {
    for_each = var.stream_enabled ? [1] : []
    content {
      enabled   = true
      view_type = var.stream_view_type
    }
  }

  # ============================================================================
  # TAGS
  # ============================================================================

  tags = merge(
    var.tags,
    {
      Name = var.table_name
    }
  )

  # Protección contra eliminación accidental (comentar para testing)
  lifecycle {
    prevent_destroy = false  # Cambiar a true en producción
  }
}

# ============================================================================
# AUTO-SCALING (Solo para Provisioned mode)
# ============================================================================
# Ajusta automáticamente RCU/WCU según demanda

resource "aws_appautoscaling_target" "dynamodb_table_read" {
  count = var.billing_mode == "PROVISIONED" && var.enable_autoscaling ? 1 : 0

  max_capacity       = var.autoscaling_read_max_capacity
  min_capacity       = var.read_capacity
  resource_id        = "table/${aws_dynamodb_table.main.name}"
  scalable_dimension = "dynamodb:table:ReadCapacityUnits"
  service_namespace  = "dynamodb"
}

resource "aws_appautoscaling_policy" "dynamodb_table_read_policy" {
  count = var.billing_mode == "PROVISIONED" && var.enable_autoscaling ? 1 : 0

  name               = "${var.table_name}-read-autoscaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.dynamodb_table_read[0].resource_id
  scalable_dimension = aws_appautoscaling_target.dynamodb_table_read[0].scalable_dimension
  service_namespace  = aws_appautoscaling_target.dynamodb_table_read[0].service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "DynamoDBReadCapacityUtilization"
    }
    target_value = var.autoscaling_read_target
  }
}

resource "aws_appautoscaling_target" "dynamodb_table_write" {
  count = var.billing_mode == "PROVISIONED" && var.enable_autoscaling ? 1 : 0

  max_capacity       = var.autoscaling_write_max_capacity
  min_capacity       = var.write_capacity
  resource_id        = "table/${aws_dynamodb_table.main.name}"
  scalable_dimension = "dynamodb:table:WriteCapacityUnits"
  service_namespace  = "dynamodb"
}

resource "aws_appautoscaling_policy" "dynamodb_table_write_policy" {
  count = var.billing_mode == "PROVISIONED" && var.enable_autoscaling ? 1 : 0

  name               = "${var.table_name}-write-autoscaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.dynamodb_table_write[0].resource_id
  scalable_dimension = aws_appautoscaling_target.dynamodb_table_write[0].scalable_dimension
  service_namespace  = aws_appautoscaling_target.dynamodb_table_write[0].service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "DynamoDBWriteCapacityUtilization"
    }
    target_value = var.autoscaling_write_target
  }
}

# ============================================================================
# CLOUDWATCH ALARMS
# ============================================================================
# Monitoreo de métricas críticas

resource "aws_cloudwatch_metric_alarm" "read_throttle_events" {
  count = var.enable_alarms ? 1 : 0

  alarm_name          = "${var.table_name}-read-throttle-events"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "ReadThrottleEvents"
  namespace           = "AWS/DynamoDB"
  period              = 300
  statistic           = "Sum"
  threshold           = 10
  alarm_description   = "Alerta cuando hay throttling de lecturas"
  treat_missing_data  = "notBreaching"

  dimensions = {
    TableName = aws_dynamodb_table.main.name
  }

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "write_throttle_events" {
  count = var.enable_alarms ? 1 : 0

  alarm_name          = "${var.table_name}-write-throttle-events"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "WriteThrottleEvents"
  namespace           = "AWS/DynamoDB"
  period              = 300
  statistic           = "Sum"
  threshold           = 10
  alarm_description   = "Alerta cuando hay throttling de escrituras"
  treat_missing_data  = "notBreaching"

  dimensions = {
    TableName = aws_dynamodb_table.main.name
  }

  tags = var.tags
}
