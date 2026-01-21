# Guía de Testing Completa

## 🎯 Objetivo

Esta guía te permite validar que toda la infraestructura y la aplicación funcionan correctamente end-to-end.

---

## 📋 Pre-requisitos de Testing

Asegúrate de tener desplegado el ambiente:

```bash
cd terraform/envs/dev
terraform apply
```

Obtén las variables necesarias:

```bash
# Guardar en variables de shell
export API_URL=$(terraform output -raw api_gateway_url)
export TABLE_NAME=$(terraform output -raw dynamodb_table_name)
export LAMBDA_NAME=$(terraform output -raw lambda_function_name)
```

---

## 🧪 Test 1: Crear Producto (Write → DynamoDB)

```bash
curl -X POST "${API_URL}/products" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "iPhone 15 Pro",
    "category": "electronics",
    "price": 999.99,
    "description": "Latest iPhone model",
    "stock": 50
  }' | jq
```

**Resultado esperado:**
```json
{
  "message": "Product created successfully",
  "product": {
    "ProductID": "uuid-aqui",
    "Version": 1705420800000,
    "Name": "iPhone 15 Pro",
    ...
  },
  "metadata": {
    "usedDAX": false,
    "operation": "write"
  }
}
```

**Validaciones:**
- ✓ Status code: 201
- ✓ `usedDAX`: false (writes no usan DAX)
- ✓ `ProductID` es UUID válido
- ✓ `Version` es timestamp

**Guardar ProductID para siguientes tests:**
```bash
export PRODUCT_ID="copiar-uuid-aqui"
```

---

## 🧪 Test 2: Leer Producto - Primera Vez (Cache Miss)

```bash
# Primera lectura
time curl -X GET "${API_URL}/products/${PRODUCT_ID}" | jq
```

**Resultado esperado:**
```json
{
  "product": {
    "ProductID": "uuid",
    ...
  },
  "metadata": {
    "usedDAX": true,
    "operation": "read",
    "latencyMs": 12,
    "cacheNote": "This read went through DAX..."
  }
}
```

**Validaciones:**
- ✓ Status code: 200
- ✓ `usedDAX`: true
- ✓ `latencyMs`: ~10-15ms (cache miss, lee de DynamoDB)
- ✓ Header `X-Using-DAX: true`

---

## 🧪 Test 3: Leer Producto - Segunda Vez (Cache Hit)

```bash
# Repetir inmediatamente
time curl -X GET "${API_URL}/products/${PRODUCT_ID}" | jq
```

**Resultado esperado:**
```json
{
  "product": { ... },
  "metadata": {
    "usedDAX": true,
    "operation": "read",
    "latencyMs": 2,  ← MÁS RÁPIDO
    ...
  }
}
```

**Validaciones:**
- ✓ `latencyMs`: ~1-3ms (cache hit!)
- ✓ Tiempo total de curl más rápido

**Este es el comportamiento clave de DAX: segunda lectura mucho más rápida**

---

## 🧪 Test 4: Listar Productos

```bash
curl -X GET "${API_URL}/products" | jq
```

**Con filtro por categoría:**
```bash
curl -X GET "${API_URL}/products?category=electronics" | jq
```

**Resultado esperado:**
```json
{
  "products": [
    { "ProductID": "...", "Name": "iPhone 15 Pro", ... }
  ],
  "count": 1,
  "metadata": {
    "usedDAX": true,
    "operation": "read",
    "latencyMs": 5
  }
}
```

**Validaciones:**
- ✓ Array de productos
- ✓ Filtro por categoría funciona (usa GSI)
- ✓ DAX cachea queries

---

## 🧪 Test 5: Actualizar Producto (Write)

```bash
curl -X PUT "${API_URL}/products/${PRODUCT_ID}" \
  -H "Content-Type: application/json" \
  -d '{
    "price": 899.99,
    "stock": 45
  }' | jq
```

**Resultado esperado:**
```json
{
  "message": "Product updated successfully",
  "product": {
    "Price": 899.99,
    "Stock": 45,
    "UpdatedAt": 1705420900000,
    ...
  },
  "metadata": {
    "usedDAX": false,
    "operation": "write",
    "note": "DAX cache will be invalidated automatically"
  }
}
```

**Validaciones:**
- ✓ Campos actualizados correctamente
- ✓ `usedDAX`: false (writes a DynamoDB)
- ✓ Nueva `Version` creada

**Ahora lee el producto para confirmar cache invalidation:**
```bash
curl -X GET "${API_URL}/products/${PRODUCT_ID}" | jq '.product.Price'
# Debe retornar 899.99 (nueva versión)
```

---

## 🧪 Test 6: Eliminar Producto

```bash
curl -X DELETE "${API_URL}/products/${PRODUCT_ID}" | jq
```

**Resultado esperado:**
```json
{
  "message": "Product deleted successfully",
  "metadata": {
    "usedDAX": false,
    "operation": "write"
  }
}
```

**Verificar que fue eliminado:**
```bash
curl -X GET "${API_URL}/products/${PRODUCT_ID}"
# Debe retornar 404 Not Found
```

---

## 🧪 Test 7: Crear Múltiples Productos (Load Test Básico)

```bash
#!/bin/bash
# Script para crear 100 productos

for i in {1..100}; do
  curl -X POST "${API_URL}/products" \
    -H "Content-Type: application/json" \
    -d "{
      \"name\": \"Product $i\",
      \"category\": \"test\",
      \"price\": $((RANDOM % 1000 + 1)).99,
      \"stock\": $((RANDOM % 100))
    }" &
done
wait

echo "100 productos creados"
```

**Validar en DynamoDB:**
```bash
aws dynamodb scan \
  --table-name ${TABLE_NAME} \
  --select COUNT
```

---

## 📊 Validación de Métricas

### CloudWatch Métricas - DAX

```bash
# Cache hits
aws cloudwatch get-metric-statistics \
  --namespace AWS/DAX \
  --metric-name ItemCacheHits \
  --dimensions Name=ClusterName,Value=dynamo-dax-demo-dev-dax \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Sum

# Cache misses
aws cloudwatch get-metric-statistics \
  --namespace AWS/DAX \
  --metric-name ItemCacheMisses \
  --dimensions Name=ClusterName,Value=dynamo-dax-demo-dev-dax \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Sum
```

**Calcular cache hit rate:**
```
Cache Hit Rate = ItemCacheHits / (ItemCacheHits + ItemCacheMisses) * 100
```

**Objetivo:** > 70% para justificar el costo de DAX

### CloudWatch Logs - Lambda

```bash
# Ver logs en tiempo real
aws logs tail /aws/lambda/${LAMBDA_NAME} --follow

# Buscar errores
aws logs filter-log-events \
  --log-group-name /aws/lambda/${LAMBDA_NAME} \
  --filter-pattern "ERROR"

# Buscar latencias altas
aws logs filter-log-events \
  --log-group-name /aws/lambda/${LAMBDA_NAME} \
  --filter-pattern "latencyMs" | jq '.events[].message'
```

---

## 🔬 Tests Avanzados

### Test de Cache Invalidation

1. Crear producto
2. Leer 2 veces (cache hit en segunda)
3. Actualizar producto
4. Leer inmediatamente → Debe retornar valores actualizados (cache invalidated)

### Test de TTL

Si habilitaste TTL:

```bash
# Crear producto con ExpiresAt
curl -X POST "${API_URL}/products" \
  -d '{
    "name": "Temporary Product",
    "category": "test",
    "price": 1.00,
    "ttl": true
  }'

# Esperar > 30 días (o cambiar TTL en código)
# Verificar que DynamoDB eliminó el item automáticamente
```

### Test de GSI

```bash
# Crear productos en diferentes categorías
curl -X POST "${API_URL}/products" \
  -d '{"name":"Laptop","category":"electronics","price":1000}'

curl -X POST "${API_URL}/products" \
  -d '{"name":"Chair","category":"furniture","price":200}'

# Query por categoría (usa CategoryIndex GSI)
curl "${API_URL}/products?category=electronics" | jq '.count'
# Debe retornar solo productos de electronics
```

---

## 🐛 Troubleshooting Tests

### Error: Connection timeout

**Causa:** Lambda no puede conectar a DAX

**Debug:**
```bash
# Verificar configuración VPC de Lambda
aws lambda get-function-configuration \
  --function-name ${LAMBDA_NAME} \
  --query 'VpcConfig'

# Debe tener: SubnetIds y SecurityGroupIds
```

### Error: "TABLE_NAME not configured"

**Causa:** Variable de entorno no pasada a Lambda

**Debug:**
```bash
aws lambda get-function-configuration \
  --function-name ${LAMBDA_NAME} \
  --query 'Environment.Variables'
```

### Error: "DAX endpoint not found"

**Causa:** Cluster DAX aún no está ready (tarda 15-20 min)

**Debug:**
```bash
aws dax describe-clusters \
  --cluster-name dynamo-dax-demo-dev-dax \
  --query 'Clusters[0].Status'

# Debe estar "available"
```

### Cache hit rate = 0%

**Causas posibles:**
1. Lambda usando cliente DynamoDB directo (no DAX)
2. TTL del cache muy bajo
3. Items muy grandes

**Debug:**
```bash
# Ver logs de Lambda para confirmar uso de DAX
aws logs tail /aws/lambda/${LAMBDA_NAME} --follow | grep "DAX"
```

---

## ✅ Checklist de Validación Final

- [ ] Crear producto funciona (201, usedDAX=false)
- [ ] Leer producto primera vez (~10ms)
- [ ] Leer producto segunda vez (~1-3ms) ← KEY VALIDATION
- [ ] Listar productos funciona
- [ ] Filtro por categoría usa GSI
- [ ] Actualizar producto funciona
- [ ] Eliminar producto funciona
- [ ] Cache hit rate > 70%
- [ ] No hay errores en CloudWatch Logs
- [ ] Latencias dentro de SLA
- [ ] Header X-Using-DAX presente

---

**Si todos los tests pasan, tu infraestructura está funcionando correctamente!** 🎉
