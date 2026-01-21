# Errores Comunes y Soluciones

## 🚨 Problemas Frecuentes

### 1. Terraform: Error creating DAX cluster

**Error:**
```
Error: error creating DAX Cluster: InvalidParameterValue: Subnets in different VPCs
```

**Causa:** Las subnets especificadas no están en la misma VPC

**Solución:**
```bash
# Verificar que todas las subnets pertenecen a la misma VPC
aws ec2 describe-subnets \
  --subnet-ids subnet-xxx subnet-yyy \
  --query 'Subnets[*].[SubnetId,VpcId]' \
  --output table

# Asegurarse de pasar subnets del mismo módulo networking
```

---

### 2. Lambda: Cannot connect to DAX

**Error en logs:**
```
Error: getaddrinfo ENOTFOUND <dax-endpoint>
```

**Causas posibles:**

**a) Lambda no está en VPC:**
```bash
# Verificar
aws lambda get-function-configuration \
  --function-name <name> \
  --query 'VpcConfig'

# Debe retornar SubnetIds y SecurityGroupIds
```

**b) Security groups no permiten tráfico:**
```bash
# Security group de Lambda debe permitir egress a 8111
# Security group de DAX debe permitir ingress desde Lambda SG en puerto 8111
```

**c) DAX cluster aún no está ready:**
```bash
aws dax describe-clusters --cluster-name <name>
# Status debe ser "available"
```

**Solución completa:**
1. Verificar Lambda en VPC con `terraform plan`
2. Revisar security groups en [terraform/envs/dev/main.tf](terraform/envs/dev/main.tf)
3. Esperar 15-20 min después de `terraform apply` para que DAX esté ready

---

### 3. Backend state: Error acquiring lock

**Error:**
```
Error: Error acquiring the state lock
ConditionalCheckFailedException: The conditional request failed
```

**Causa:** Otro proceso de Terraform está corriendo o quedó bloqueado

**Solución:**

**Opción 1 - Esperar:** Otro usuario/CI está ejecutando Terraform

**Opción 2 - Force unlock (PELIGROSO):**
```bash
# Obtener lock ID del error message
terraform force-unlock <LOCK_ID>
```

**Opción 3 - Eliminar lock de DynamoDB (ÚLTIMO RECURSO):**
```bash
aws dynamodb delete-item \
  --table-name dynamo-demo-tfstate-lock \
  --key '{"LockID": {"S": "<lock-id>"}}'
```

⚠️ **SOLO usar force-unlock si estás SEGURO de que no hay otro Terraform corriendo**

---

### 4. npm install: Module not found

**Error:**
```
Error: Cannot find module 'amazon-dax-client'
```

**Causa:** Dependencias no instaladas antes de crear zip de Lambda

**Solución:**
```bash
cd app/
npm install
cd ../terraform/envs/dev
terraform apply
```

---

### 5. API Gateway: 502 Bad Gateway

**Error al hacer request:**
```json
{
  "message": "Internal server error"
}
```

**Causas posibles:**

**a) Lambda crasheando:**
```bash
# Ver logs
aws logs tail /aws/lambda/<function-name> --follow

# Buscar errores
aws logs filter-log-events \
  --log-group-name /aws/lambda/<function-name> \
  --filter-pattern "ERROR"
```

**b) Timeout de Lambda:**
```bash
# Verificar timeout (default: 30s)
aws lambda get-function-configuration \
  --function-name <name> \
  --query 'Timeout'

# Si es muy bajo, aumentar en variables.tf
```

**c) Lambda sin permisos:**
```bash
# Verificar IAM role
aws lambda get-function-configuration \
  --function-name <name> \
  --query 'Role'

# Verificar policies del role
aws iam list-attached-role-policies \
  --role-name <role-name>
```

---

### 6. DynamoDB: ProvisionedThroughputExceededException

**Error en logs:**
```
ProvisionedThroughputExceededException: The level of configured provisioned throughput for the table was exceeded
```

**Causa:** En modo PROVISIONED, se excedió RCU/WCU

**Solución:**

**Opción 1 - Cambiar a On-Demand:**
```hcl
# En terraform/modules/dynamodb/main.tf
billing_mode = "PAY_PER_REQUEST"
```

**Opción 2 - Aumentar capacidad:**
```hcl
billing_mode   = "PROVISIONED"
read_capacity  = 10  # Aumentar
write_capacity = 10  # Aumentar
```

**Opción 3 - Habilitar auto-scaling:**
```hcl
enable_autoscaling = true
```

---

### 7. Terraform: State file is locked

**Error:**
```
Error: state lock already held
```

**Causa:** Interrupción previa de Terraform

**Solución:**
```bash
# Listar locks en DynamoDB
aws dynamodb scan \
  --table-name dynamo-demo-tfstate-lock \
  --projection-expression "LockID"

# Force unlock
terraform force-unlock <LOCK_ID>
```

---

### 8. DAX: Cache hit rate es 0%

**Síntoma:** Métricas muestran solo cache misses

**Causas:**

**a) Lambda usando cliente DynamoDB directo:**
```javascript
// INCORRECTO
const client = new AWS.DynamoDB.DocumentClient();

// CORRECTO
const { getReadClient } = require('./clients/dynamoClient');
const client = getReadClient();
```

**b) ENV var DAX_ENDPOINT no configurada:**
```bash
aws lambda get-function-configuration \
  --function-name <name> \
  --query 'Environment.Variables.DAX_ENDPOINT'

# Debe retornar endpoint del cluster DAX
```

**c) TTL del cache muy bajo:**
```bash
# Verificar parameter group de DAX
aws dax describe-parameter-groups \
  --parameter-group-name <name>

# Ajustar TTL en terraform/modules/dax/main.tf
```

---

### 9. Cost Explorer: Costos inesperadamente altos

**Síntoma:** Factura de AWS alta

**Áreas a revisar:**

**NAT Gateway ($32/mes por gateway):**
```bash
# Verificar cuántas NAT gateways tienes
aws ec2 describe-nat-gateways \
  --filter "Name=state,Values=available" \
  --query 'NatGateways[*].[NatGatewayId,SubnetId]'

# En dev, usar single_nat_gateway = true
```

**DAX ($29-$600/mes según node type):**
```bash
# Verificar tipo de nodo
aws dax describe-clusters \
  --query 'Clusters[*].[ClusterName,NodeType,TotalNodes]'

# En dev, usar dax.t3.small con 1 nodo
```

**DynamoDB On-Demand:**
```bash
# Si tráfico es predecible, cambiar a provisioned
billing_mode = "PROVISIONED"
```

**VPC Flow Logs:**
```bash
# Deshabilitar en dev si no es necesario
enable_flow_logs = false
```

---

### 10. Git: Accidentally committed secrets

**Error:** Credenciales en Git

**Solución URGENTE:**

```bash
# 1. Rotar credenciales inmediatamente en AWS
aws iam delete-access-key --access-key-id <KEY>
aws iam create-access-key --user-name <USER>

# 2. Remover del historial de Git
git filter-branch --force --index-filter \
  "git rm --cached --ignore-unmatch <file-with-secrets>" \
  --prune-empty --tag-name-filter cat -- --all

# 3. Force push (cuidado!)
git push origin --force --all

# 4. Agregar a .gitignore
echo "<file-pattern>" >> .gitignore
```

**Prevención:**
- Usar AWS Secrets Manager o SSM Parameter Store
- Nunca hardcodear credenciales
- Variables sensibles en `*.tfvars` (que está en .gitignore)
- Pre-commit hooks con `git-secrets`

---

## 🔍 Debugging General

### Ver todos los recursos creados

```bash
cd terraform/envs/dev
terraform state list
```

### Ver configuración de un recurso

```bash
terraform state show <resource-type>.<name>
```

### Ver outputs

```bash
terraform output
terraform output -json
```

### Recrear un recurso específico

```bash
# Marcar para recrear
terraform taint <resource-type>.<name>

# Aplicar solo ese recurso
terraform apply -target=<resource-type>.<name>
```

### Importar recurso existente

```bash
# Si creaste algo manual en AWS
terraform import <resource-type>.<name> <aws-resource-id>
```

---

## 📞 Soporte

Si ninguna de estas soluciones funciona:

1. Revisar CloudWatch Logs
2. Revisar CloudTrail events
3. Ejecutar `terraform plan` para ver drift
4. Consultar [AWS Service Health Dashboard](https://status.aws.amazon.com/)

---

**Recuerda:** La mayoría de errores son de configuración, no bugs. Lee los mensajes de error detenidamente! 🔍
