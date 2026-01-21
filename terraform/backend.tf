# ============================================================================
# TERRAFORM BACKEND CONFIGURATION
# ============================================================================
# Este archivo configura el backend remoto de Terraform usando S3 + DynamoDB
# 
# DECISIÓN DE ARQUITECTURA:
# --------------------------
# ¿Por qué backend remoto?
# - State compartido entre el equipo
# - Locking para prevenir modificaciones concurrentes
# - Backup automático del state
# - Historial de cambios
# 
# SETUP INICIAL (Ejecutar primero):
# ---------------------------------
# 1. cd terraform/bootstrap
# 2. terraform init && terraform apply
# 3. Volver aquí y descomentar este bloque
# 4. terraform init -migrate-state
# 
# TRADE-OFFS:
# -----------
# ✅ PRO: State seguro, colaborativo, versionado
# ❌ CON: Dependencia de AWS para operations (incluso plan/destroy)
# ❌ CON: Costo adicional (mínimo: ~$0.023/mes S3 + $0.25/mes DynamoDB)
# 
# ALTERNATIVAS CONSIDERADAS:
# -------------------------
# 1. Backend local: Rechazado - no funciona en equipos
# 2. Terraform Cloud: Válido para empresas, pero agrega dependencia externa
# 3. GitLab/GitHub: Requiere configuración CI/CD más compleja
# ============================================================================

# COMENTADO INICIALMENTE - Descomentar después del bootstrap
# terraform {
#   backend "s3" {
#     bucket         = "dynamo-demo-tfstate-${var.environment}"
#     key            = "terraform.tfstate"
#     region         = "us-east-1"
#     dynamodb_table = "dynamo-demo-tfstate-lock"
#     encrypt        = true
#     
#     # IMPORTANTE: Estas son las recomendaciones mínimas de seguridad
#     # En producción real, agregar:
#     # - kms_key_id para encryption específica
#     # - workspace_key_prefix para múltiples workspaces
#   }
# }

# ============================================================================
# ¿QUÉ DIRÍA UN SENIOR EN UNA ENTREVISTA?
# ============================================================================
# "Usamos backend remoto en S3 porque necesitamos colaboración segura.
# El locking con DynamoDB previene race conditions. Implementamos esto
# mediante un módulo bootstrap separado para evitar el chicken-egg problem.
# El state está encriptado y versionado. En un escenario real, añadiría
# MFA delete y replication cross-region para disaster recovery."
# ============================================================================
