# Quick Start Guide

## 🚀 Deployment en 5 Minutos

### Opción 1: Usando el script helper (Recomendado)

```bash
# 1. Verificar requisitos
./scripts/deploy.sh check

# 2. Bootstrap del backend
./scripts/deploy.sh bootstrap

# 3. Deploy ambiente dev
./scripts/deploy.sh deploy dev

# 4. Testing
./scripts/deploy.sh test dev
```

### Opción 2: Manual

```bash
# 1. Bootstrap
cd terraform/bootstrap
terraform init && terraform apply

# 2. Configurar backend
# Editar terraform/backend.tf (descomentar bloque)

# 3. Deploy
cd ../envs/dev
npm install --prefix ../../../app
terraform init && terraform apply

# 4. Testing
API_URL=$(terraform output -raw api_gateway_url)
curl -X POST "${API_URL}/products" \
  -H "Content-Type: application/json" \
  -d '{"name":"Test","category":"test","price":9.99}'
```

---

## 📍 Comandos Útiles

### Ver logs de Lambda en tiempo real
```bash
aws logs tail /aws/lambda/$(cd terraform/envs/dev && terraform output -raw lambda_function_name) --follow
```

### Ver métricas de DAX
```bash
aws cloudwatch get-metric-statistics \
  --namespace AWS/DAX \
  --metric-name ItemCacheHits \
  --dimensions Name=ClusterName,Value=dynamo-dax-demo-dev-dax \
  --start-time $(date -u -d '10 minutes ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Sum
```

### Limpiar todo
```bash
./scripts/deploy.sh destroy dev
cd terraform/bootstrap && terraform destroy
```

---

## 🎯 Para Entrevistas

**Pregunta clave:** "Explica tu proyecto más complejo en AWS"

**Tu respuesta:**
"Diseñé e implementé una arquitectura production-ready en AWS con DynamoDB y DAX. La infraestructura está completamente en Terraform con módulos reutilizables para múltiples ambientes. Implementé separación entre writes (directo a DynamoDB) y reads (vía DAX) logrando latencias sub-milisegundo. La aplicación Lambda demuestra funcionalidad end-to-end con API Gateway. Todo con least privilege IAM, VPC privada, monitoring y documentación completa."

**Puntos a destacar:**
- ✅ IaC con Terraform modular
- ✅ Arquitectura multi-ambiente
- ✅ Seguridad (IAM, VPC, encryption)
- ✅ Performance (DAX cache)
- ✅ Observabilidad (CloudWatch)
- ✅ Costos optimizados por ambiente
- ✅ Aplicación funcional, no solo infra

---

## 📚 Documentación Completa

- [README.md](../README.md) - Visión general
- [TESTING.md](TESTING.md) - Guía de testing detallada
- [COMMON_ERRORS.md](COMMON_ERRORS.md) - Troubleshooting

---

**¡Listo para impresionar en tu entrevista!** 💪
