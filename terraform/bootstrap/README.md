# Bootstrap Infrastructure

## 🎯 Propósito

Este directorio contiene la infraestructura de bootstrap necesaria para configurar el backend remoto de Terraform (S3 + DynamoDB).

**DEBE ejecutarse PRIMERO**, antes que cualquier otro módulo de Terraform.

## 🏗️ ¿Qué crea?

1. **S3 Bucket** (`dynamo-demo-tfstate-bootstrap`)
   - Almacena el state de Terraform
   - Versionado habilitado (permite rollback)
   - Encriptación AES256
   - Acceso público bloqueado
   - Lifecycle policies para versiones antiguas

2. **DynamoDB Table** (`dynamo-demo-tfstate-lock`)
   - Gestiona locking del state
   - Previene modificaciones concurrentes
   - Billing: PAY_PER_REQUEST (costo mínimo)
   - Point-in-time recovery habilitado

## 🚀 Instrucciones de uso

### 1. Ejecutar bootstrap (primera vez)

```bash
cd terraform/bootstrap
terraform init
terraform plan
terraform apply
```

### 2. Copiar configuración del backend

Después del `apply`, copia la salida `backend_config` al archivo `terraform/backend.tf` (descomentando el bloque).

### 3. Migrar state

```bash
cd ..  # Volver a terraform/
terraform init -migrate-state
```

Terraform preguntará si quieres migrar el state local a S3. Responde `yes`.

## 🔒 Seguridad

- ✅ Bucket privado (no public access)
- ✅ Encriptación en reposo
- ✅ Versionado habilitado
- ✅ Lifecycle prevent_destroy
- ⚠️ **TODO para producción:**
  - Agregar KMS CMK para encriptación
  - Habilitar MFA delete
  - Configurar replication cross-region
  - Implementar bucket logging

## 💰 Costos

**Estimados mensuales (uso bajo):**
- S3: ~$0.023/mes (1 GB)
- DynamoDB: $0.25/mes (on-demand mínimo)
- **Total: ~$0.27/mes**

## ⚠️ Advertencias

1. **NO ejecutar `terraform destroy`** sin antes migrar el state
2. Este módulo tiene `prevent_destroy = true` como protección
3. Si necesitas destruir, primero:
   ```bash
   # En terraform/ principal
   terraform init -migrate-state -backend=false
   # Luego sí puedes destruir bootstrap
   ```

## 🤔 Preguntas de entrevista

**P: ¿Por qué separar el bootstrap?**
R: Evita el problema chicken-egg. No puedes crear el backend con backend remoto. Se crea con backend local primero, luego se migra.

**P: ¿Por qué PAY_PER_REQUEST en DynamoDB?**
R: El locking table tiene tráfico mínimo e impredecible. On-demand evita overprovisioning y es más barato para uso bajo.

**P: ¿Qué pasa si se corrompe el state?**
R: Con versionado habilitado, podemos recuperar versiones anteriores desde la consola de S3 o usando `aws s3api`.

**P: ¿Es seguro este setup para producción?**
R: Es un buen punto de partida, pero producción requiere:
- KMS CMK encryption
- Cross-region replication
- MFA delete
- CloudTrail logging
- Backup policies adicionales
