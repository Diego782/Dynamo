# ============================================================================
# BOOTSTRAP INFRASTRUCTURE
# ============================================================================
# Este módulo crea la infraestructura necesaria para el backend remoto.
# DEBE ejecutarse PRIMERO, con backend local.
# 
# Crea:
# - S3 bucket para el state de Terraform
# - DynamoDB table para locking
# - Políticas de seguridad y versionado
# ============================================================================

terraform {
  required_version = ">= 1.6.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = "DynamoDAX-Demo"
      ManagedBy   = "Terraform"
      Environment = "bootstrap"
      Owner       = "DevOps-Team"
    }
  }
}

# ============================================================================
# S3 BUCKET PARA TERRAFORM STATE
# ============================================================================

resource "aws_s3_bucket" "terraform_state" {
  bucket = var.state_bucket_name

  # Prevenir eliminación accidental del bucket con el state
  lifecycle {
    prevent_destroy = true
  }

  tags = {
    Name        = "Terraform State Bucket"
    Description = "Stores Terraform state files"
  }
}

# Versionado del state (permite rollback)
resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Encriptación en reposo
resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
      # En producción: usar KMS con key rotation
      # kms_master_key_id = aws_kms_key.terraform.arn
      # sse_algorithm     = "aws:kms"
    }
  }
}

# Bloquear acceso público
resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Lifecycle policy para gestionar versiones antiguas
resource "aws_s3_bucket_lifecycle_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    id     = "delete-old-versions"
    status = "Enabled"

    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }

  rule {
    id     = "abort-incomplete-uploads"
    status = "Enabled"

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# ============================================================================
# DYNAMODB TABLE PARA STATE LOCKING
# ============================================================================

resource "aws_dynamodb_table" "terraform_locks" {
  name           = var.dynamodb_table_name
  billing_mode   = "PAY_PER_REQUEST"  # On-demand - uso mínimo esperado
  hash_key       = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  # Point-in-time recovery por seguridad
  point_in_time_recovery {
    enabled = true
  }

  # Encriptación con AWS managed key
  server_side_encryption {
    enabled = true
    # En producción: CMK específica
    # kms_key_arn = aws_kms_key.terraform.arn
  }

  tags = {
    Name        = "Terraform State Lock Table"
    Description = "Manages Terraform state locking"
  }

  lifecycle {
    prevent_destroy = true
  }
}

# ============================================================================
# OUTPUTS
# ============================================================================

output "state_bucket_name" {
  description = "Nombre del bucket S3 para el state"
  value       = aws_s3_bucket.terraform_state.id
}

output "state_bucket_arn" {
  description = "ARN del bucket S3"
  value       = aws_s3_bucket.terraform_state.arn
}

output "dynamodb_table_name" {
  description = "Nombre de la tabla DynamoDB para locking"
  value       = aws_dynamodb_table.terraform_locks.id
}

output "backend_config" {
  description = "Configuración para copiar en backend.tf"
  value = <<-EOT
    terraform {
      backend "s3" {
        bucket         = "${aws_s3_bucket.terraform_state.id}"
        key            = "terraform.tfstate"
        region         = "${var.region}"
        dynamodb_table = "${aws_dynamodb_table.terraform_locks.id}"
        encrypt        = true
      }
    }
  EOT
}
