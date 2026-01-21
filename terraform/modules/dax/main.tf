# ============================================================================
# DAX (DynamoDB Accelerator) MODULE
# ============================================================================
# DAX es un cache in-memory para DynamoDB
# 
# ARQUITECTURA:
# =============
# Application → DAX Cluster → DynamoDB
#   READ ✅         ↓              ↓
#   WRITE ❌    Cache Hit      Primary Store
# 
# ============================================================================
# DECISIONES CLAVE DE ARQUITECTURA
# ============================================================================
# 
# 1. ¿CUÁNDO USAR DAX?
# --------------------
# ✅ Casos de uso ideales:
#   - Lecturas repetidas del mismo dato (e.g., product details)
#   - Latencia crítica (< 1ms vs ~10ms DynamoDB)
#   - Read-heavy workloads (ratio lectura/escritura > 10:1)
#   - Hot keys (algunos items muy populares)
# 
# ❌ Cuándo NO usar DAX:
#   - Write-heavy workloads
#   - Datos que cambian constantemente
#   - Queries complejas (DAX no cachea Scans)
#   - Budget limitado (costo significativo)
# 
# 2. TIPO DE NODO
# ---------------
# Opciones (ordenadas por costo/performance):
#   - dax.t3.small:  2 vCPU, 1.5 GB RAM   (~$0.04/hr)  ✅ Dev/Staging
#   - dax.t3.medium: 2 vCPU, 3 GB RAM     (~$0.08/hr)
#   - dax.r5.large:  2 vCPU, 16 GB RAM    (~$0.28/hr)  ✅ Producción pequeña
#   - dax.r5.xlarge: 4 vCPU, 32 GB RAM    (~$0.56/hr)  ✅ Producción media
# 
# ENTREVISTA: "Comenzamos con dax.t3.small en dev para testing.
# En producción, evaluamos métricas (CPUUtilization, CacheMisses)
# y escalamos a dax.r5.large basándonos en working set size."
# 
# 3. TAMAÑO DEL CLUSTER
# ---------------------
# - Mínimo: 1 nodo (dev/testing)
# - Recomendado producción: 3+ nodos (high availability)
# - Máximo: 10 nodos
# 
# Multi-AZ deployment = High Availability
# 
# 4. TTL DEL CACHE
# ----------------
# - Item Cache TTL: Cuánto tiempo cachear items individuales
#   Recomendado: 5-10 minutos para datos relativamente estáticos
# 
# - Query Cache TTL: Cuánto tiempo cachear resultados de queries
#   Recomendado: Más bajo que item cache (1-5 min)
# 
# Trade-off: TTL alto = mejor performance, pero datos más stale
# ============================================================================

# ============================================================================
# SUBNET GROUP
# ============================================================================
# DAX debe estar en subnets privadas (no necesita internet access)

resource "aws_dax_subnet_group" "main" {
  name       = "${var.cluster_name}-subnet-group"
  subnet_ids = var.subnet_ids

  description = "Subnet group for ${var.cluster_name} DAX cluster"
}

# ============================================================================
# PARAMETER GROUP
# ============================================================================
# Configuración del comportamiento del cache

resource "aws_dax_parameter_group" "main" {
  name = "${var.cluster_name}-params"

  # TTL del cache para items individuales
  parameters {
    name  = "query-ttl-millis"
    value = tostring(var.query_cache_ttl_seconds * 1000)
  }

  parameters {
    name  = "record-ttl-millis"
    value = tostring(var.item_cache_ttl_seconds * 1000)
  }

  description = "Parameter group for ${var.cluster_name}"
}

# ============================================================================
# SECURITY GROUP
# ============================================================================
# Control de acceso al cluster DAX
# DAX usa puerto 8111 (encriptado) o 8222 (no encriptado)

resource "aws_security_group" "dax" {
  name_prefix = "${var.cluster_name}-dax-"
  description = "Security group for ${var.cluster_name} DAX cluster"
  vpc_id      = var.vpc_id

  # Ingress: Permitir tráfico desde Lambda/EC2
  ingress {
    description     = "DAX encrypted port from app security group"
    from_port       = 8111
    to_port         = 8111
    protocol        = "tcp"
    security_groups = var.allowed_security_group_ids
  }

  # Ingress: Comunicación entre nodos del cluster
  ingress {
    description = "DAX cluster node communication"
    from_port   = 8111
    to_port     = 8111
    protocol    = "tcp"
    self        = true
  }

  # Egress: DAX necesita acceso a DynamoDB
  # Opción 1: Via internet (NAT Gateway)
  # Opción 2: Via VPC endpoint (más seguro, sin costo de NAT)
  egress {
    description = "Allow outbound to DynamoDB"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.cluster_name}-dax-sg"
    }
  )

  lifecycle {
    create_before_destroy = true
  }
}

# ============================================================================
# DAX CLUSTER
# ============================================================================

resource "aws_dax_cluster" "main" {
  cluster_name = var.cluster_name
  iam_role_arn = var.iam_role_arn
  node_type    = var.node_type
  
  # Número de nodos
  # Dev: 1 nodo
  # Prod: 3+ nodos para HA (distribuidos en múltiples AZs)
  replication_factor = var.replication_factor

  # Configuración de subnets y seguridad
  subnet_group_name   = aws_dax_subnet_group.main.name
  security_group_ids  = [aws_security_group.dax.id]
  parameter_group_name = aws_dax_parameter_group.main.name

  # ============================================================================
  # ENCRIPTACIÓN
  # ============================================================================
  # Opción 1: Encriptación en tránsito (TLS) ✅ Recomendado
  # Opción 2: Sin encriptación (menor latencia, pero inseguro)
  
  cluster_endpoint_encryption_type = var.encryption_type

  # ============================================================================
  # MAINTENANCE WINDOW
  # ============================================================================
  # Ventana para patches y actualizaciones
  # Formato: ddd:hh24:mi-ddd:hh24:mi (UTC)
  # Ejemplo: "sun:05:00-sun:06:00" = Domingos 5-6 AM UTC
  
  maintenance_window = var.maintenance_window

  # ============================================================================
  # NOTIFICACIONES
  # ============================================================================
  # SNS topic para eventos del cluster (opcional)
  
  notification_topic_arn = var.notification_topic_arn

  # ============================================================================
  # AVAILABILITY ZONES
  # ============================================================================
  # Especificar AZs para distribución de nodos (opcional)
  # Si no se especifica, AWS distribuye automáticamente
  
  availability_zones = length(var.availability_zones) > 0 ? var.availability_zones : null

  tags = merge(
    var.tags,
    {
      Name = var.cluster_name
    }
  )

  # DAX puede tardar 15-20 minutos en crear/modificar
  timeouts {
    create = "45m"
    update = "45m"
    delete = "45m"
  }

  depends_on = [
    aws_dax_subnet_group.main,
    aws_dax_parameter_group.main
  ]
}

# ============================================================================
# CLOUDWATCH ALARMS
# ============================================================================
# Monitoreo de métricas críticas del cluster

resource "aws_cloudwatch_metric_alarm" "cache_miss_rate" {
  count = var.enable_alarms ? 1 : 0

  alarm_name          = "${var.cluster_name}-high-cache-miss-rate"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "ItemCacheMisses"
  namespace           = "AWS/DAX"
  period              = 300
  statistic           = "Sum"
  threshold           = 1000
  alarm_description   = "Alerta cuando hay muchos cache misses"
  treat_missing_data  = "notBreaching"

  dimensions = {
    ClusterName = aws_dax_cluster.main.cluster_name
  }

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "cpu_utilization" {
  count = var.enable_alarms ? 1 : 0

  alarm_name          = "${var.cluster_name}-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/DAX"
  period              = 300
  statistic           = "Average"
  threshold           = 75
  alarm_description   = "Alerta cuando CPU > 75%"
  treat_missing_data  = "notBreaching"

  dimensions = {
    ClusterName = aws_dax_cluster.main.cluster_name
  }

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "evicted_items" {
  count = var.enable_alarms ? 1 : 0

  alarm_name          = "${var.cluster_name}-high-eviction-rate"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "EvictedSize"
  namespace           = "AWS/DAX"
  period              = 300
  statistic           = "Sum"
  threshold           = 1000000  # 1 MB
  alarm_description   = "Alerta cuando se evictan muchos items (cache demasiado pequeño)"
  treat_missing_data  = "notBreaching"

  dimensions = {
    ClusterName = aws_dax_cluster.main.cluster_name
  }

  tags = var.tags
}

# ============================================================================
# ¿QUÉ DIRÍA UN SENIOR EN UNA ENTREVISTA?
# ============================================================================
# "DAX es fundamentalmente un write-through cache. Solo debe usarse
# para lecturas. Los writes van directo a DynamoDB y DAX invalida su
# cache automáticamente.
#
# Métricas críticas a monitorear:
# 1. ItemCacheMisses: Si es alto, el cache no es efectivo
# 2. CPUUtilization: Si > 75%, necesitamos escalar verticalmente (node type)
# 3. EvictedSize: Si es alto, el cache es muy pequeño (escalar horizontalmente)
#
# El trade-off principal es costo vs latencia. Un cluster de 3 nodos
# dax.r5.large cuesta ~$600/mes. Debe justificarse con:
# - Reducción mensurable de latencia (p99 < 1ms)
# - Ahorro en RCUs de DynamoDB
# - Mejora en experiencia de usuario
#
# En la práctica, lo usaríamos para catálogos de productos, perfiles
# de usuario, configuraciones - datos leídos frecuentemente pero
# actualizados raramente."
# ============================================================================
