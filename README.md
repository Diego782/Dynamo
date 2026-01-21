# DynamoDB + DAX Production-Ready Demo

> 🎯 **Proyecto diseñado para demostrar arquitectura cloud senior-level con AWS, Terraform y sistemas distribuidos**

[![Terraform](https://img.shields.io/badge/Terraform-%3E%3D1.6-623CE4?logo=terraform)](https://www.terraform.io/)
[![AWS](https://img.shields.io/badge/AWS-DynamoDB%20%2B%20DAX-FF9900?logo=amazon-aws)](https://aws.amazon.com/)
[![Node.js](https://img.shields.io/badge/Node.js-%3E%3D18-339933?logo=node.js)](https://nodejs.org/)

---

## 📋 Tabla de Contenidos

- [Descripción General](#-descripción-general)
- [Arquitectura](#-arquitectura)
- [Estructura del Proyecto](#-estructura-del-proyecto)
- [Guía de Deployment](#-guía-de-deployment)
- [Testing](#-testing)
- [Decisiones de Arquitectura](#-decisiones-de-arquitectura)
- [Costos Estimados](#-costos-estimados)
- [Troubleshooting](#-troubleshooting)
- [Preguntas de Entrevista](#-preguntas-de-entrevista)

---

## 🎯 Descripción General

Este proyecto demuestra una arquitectura **production-ready** en AWS que integra:

- **Infraestructura como Código (IaC)** con Terraform
- **DynamoDB** como base de datos NoSQL con diseño optimizado
- **DAX** (DynamoDB Accelerator) para cache in-memory de lecturas
- **Lambda + API Gateway** con aplicación real funcional
- **Multi-ambiente** (dev, staging, prod) con configuraciones diferenciadas
- **Seguridad** con IAM roles de menor privilegio
- **Networking** con VPC, subnets privadas, NAT Gateways
- **Observabilidad** con CloudWatch Logs, métricas y alarmas

### ✨ Características Principales

✅ **Infraestructura completa y modular**  
✅ **Aplicación real end-to-end** (no solo infra, sino funcionalidad comprobable)  
✅ **Separación de ambientes** con diferentes configuraciones  
✅ **Backend remoto** con state locking  
✅ **Documentación exhaustiva** con justificación de decisiones  
✅ **Ready para entrevistas técnicas senior**

---

## 🏗 Arquitectura

### Diagrama de Arquitectura

```
┌─────────────────────────────────────────────────────────────────┐
│                         AWS Cloud                                │
│                                                                   │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │                      VPC (10.0.0.0/16)                     │ │
│  │                                                            │ │
│  │  ┌──────────────────┐        ┌──────────────────┐        │ │
│  │  │  Public Subnet   │        │  Public Subnet   │        │ │
│  │  │  10.0.0.0/24     │        │  10.0.1.0/24     │        │ │
│  │  │                  │        │                  │        │ │
│  │  │  ┌────────────┐  │        │  ┌────────────┐  │        │ │
│  │  │  │ NAT Gateway│  │        │  │ NAT Gateway│  │        │ │
│  │  │  └─────┬──────┘  │        │  └─────┬──────┘  │        │ │
│  │  └────────┼─────────┘        └────────┼─────────┘        │ │
│  │           │                            │                   │ │
│  │  ┌────────▼─────────┐        ┌────────▼─────────┐        │ │
│  │  │  Private Subnet  │        │  Private Subnet  │        │ │
│  │  │  10.0.100.0/24   │        │  10.0.101.0/24   │        │ │
│  │  │                  │        │                  │        │ │
│  │  │  ┌──────────┐    │        │  ┌──────────┐    │        │ │
│  │  │  │  Lambda  │◄───┼────────┼──┤ Lambda   │    │        │ │
│  │  │  │ Function │    │        │  │ Function │    │        │ │
│  │  │  └────┬─────┘    │        │  └────┬─────┘    │        │ │
│  │  │       │          │        │       │          │        │ │
│  │  │  ┌────▼─────┐    │        │  ┌────▼─────┐    │        │ │
│  │  │  │   DAX    │◄───┼────────┼──┤   DAX    │    │        │ │
│  │  │  │  Node 1  │    │        │  │  Node 2  │    │        │ │
│  │  │  └────┬─────┘    │        │  └────┬─────┘    │        │ │
│  │  └───────┼──────────┘        └───────┼──────────┘        │ │
│  └──────────┼────────────────────────────┼───────────────────┘ │
│             │                            │                      │
│             │        ┌───────────────────▼────┐                 │
│             └───────►│                         │                 │
│                      │   DynamoDB Table        │                 │
│  ┌───────────────────┤   (Products)            │                 │
│  │  API Gateway      │                         │                 │
│  │  (HTTP API)       │   - PK: ProductID       │                 │
│  │                   │   - SK: Version         │                 │
│  └───────────────────┤   - GSI: CategoryIndex  │                 │
│         ▲            │   - TTL: ExpiresAt      │                 │
│         │            └─────────────────────────┘                 │
└─────────┼──────────────────────────────────────────────────────┘
          │
      ┌───┴────┐
      │ Client │
      │  (API) │
      └────────┘
```

### Flujo de Datos

**WRITES (POST, PUT, DELETE):**
```
Client → API Gateway → Lambda → DynamoDB (directo, sin DAX)
                                     ↓
                              DAX invalida cache
```

**READS (GET):**
```
Client → API Gateway → Lambda → DAX → Cache Hit? 
                                  ├─ YES: Return from cache (~1ms)
                                  └─ NO:  Query DynamoDB → Cache → Return (~10ms)
```

---

## 📁 Estructura del Proyecto

```
dynamo-dax-demo/
├── terraform/
│   ├── bootstrap/                    # Backend remoto (S3 + DynamoDB)
│   ├── modules/                      # Módulos reutilizables
│   │   ├── networking/               # VPC, subnets, NAT
│   │   ├── dynamodb/                 # Tabla con PITR, TTL, GSI
│   │   ├── dax/                      # Cluster DAX
│   │   ├── iam/                      # Roles y policies
│   │   └── lambda/                   # Lambda function
│   └── envs/                         # Ambientes (dev/staging/prod)
│
├── app/                              # Aplicación Lambda Node.js
│   ├── src/
│   │   ├── clients/                  # DynamoDB/DAX clients
│   │   └── handlers/                 # CRUD handlers
│   └── package.json
│
└── README.md
```

---

## 🚀 Guía de Deployment

### Prerrequisitos

- AWS Account con credenciales configuradas
- Terraform >= 1.6.0
- Node.js >= 18.x
- AWS CLI configurado

### Paso 1: Bootstrap del Backend Remoto

```bash
cd terraform/bootstrap
terraform init
terraform apply
# Guardar output de backend_config
```

### Paso 2: Configurar Backend

```bash
cd ..
# Editar backend.tf y descomentar bloque backend "s3"
terraform init -migrate-state
```

### Paso 3: Deploy DEV

```bash
cd envs/dev

# Instalar dependencias de app
cd ../../../app && npm install && cd -

terraform init
terraform plan
terraform apply  # ⚠️ DAX tarda ~15-20 minutos
```

### Paso 4: Verificar

```bash
# Obtener API URL
terraform output api_gateway_url

# Testear
curl -X POST "$(terraform output -raw api_gateway_url)/products" \
  -H "Content-Type: application/json" \
  -d '{"name":"Test Product","category":"test","price":99.99}'
```

---

## 🧪 Testing

### Crear Producto (Write → DynamoDB)

```bash
API_URL=$(cd terraform/envs/dev && terraform output -raw api_gateway_url)

curl -X POST "${API_URL}/products" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "MacBook Pro M3",
    "category": "electronics",
    "price": 2499.99,
    "stock": 10
  }'
```

### Leer Producto (Read → DAX)

```bash
# Primera lectura (cache miss ~10ms)
curl "${API_URL}/products/{PRODUCT_ID}"

# Segunda lectura (cache hit ~1ms)
curl "${API_URL}/products/{PRODUCT_ID}"
```

### Validar DAX

**Verificar métricas:**
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

**Verificar latencia:**
- Cache miss: ~10-15ms
- Cache hit: ~1-3ms

---

## 🧠 Decisiones de Arquitectura

### ¿Por qué On-Demand en DynamoDB?

✅ Sin planificación de capacidad  
✅ Auto-scaling automático  
❌ Más caro con tráfico constante  

**Prod:** Evaluar provisioned mode con auto-scaling

### ¿Por qué DAX solo para lecturas?

- DAX es write-through cache
- Writes a DAX agregan latencia innecesaria
- Pattern CQRS: separar writes y reads

### ¿Por qué Lambda en VPC?

- DAX está en subnets privadas
- Necesario para conectividad
- Trade-off: Cold start más lento (~1-2s)

---

## 💰 Costos Estimados

### DEV (1 mes)
- DynamoDB: ~$1.50
- DAX (1 x t3.small): ~$29.00
- NAT Gateway: ~$32.00
- Lambda: ~$0.20
- API Gateway: ~$1.00
- **Total: ~$64/mes**

### PROD (1 mes)
- DynamoDB: ~$15.00
- DAX (3 x r5.large): ~$612.00
- NAT Gateways (3): ~$96.00
- Lambda: ~$2.00
- API Gateway: ~$10.00
- **Total: ~$745/mes**

---

## 🔧 Troubleshooting

### Lambda no conecta a DAX

**Verificar:**
- Lambda en VPC ✓
- Security groups permiten puerto 8111 ✓
- DAX en subnets privadas ✓
- NAT Gateway configurado ✓

### Cache hit rate 0%

**Causas:**
- Lambda usando cliente DynamoDB directo
- TTL del cache muy bajo
- Verificar env var `DAX_ENDPOINT`

---

## 💼 Preguntas de Entrevista

### ¿Cómo funciona DAX?

"DAX es un cache in-memory distribuido. Cache hit retorna en ~1ms, cache miss query a DynamoDB ~10ms. Es write-through: writes van a DynamoDB y DAX invalida cache automáticamente."

### ¿Cuándo NO usar DAX?

"No usar DAX si:
- Write-heavy workload
- Datos cambian constantemente
- Strong consistency requerida
- Budget limitado
- Hot keys no identificados"

### ¿Cómo validar que DAX funciona?

"Múltiples niveles:
1. CloudWatch métricas (ItemCacheHits/Misses)
2. Latencias en aplicación (logs)
3. Testing A/B (con/sin DAX)
4. Cache hit rate > 70% para ROI positivo"

### ¿Por qué versionado en DynamoDB?

"Patrón para mantener historial:
- PK: ProductID, SK: Version (timestamp)
- Permite auditoría, rollback, compliance
- Trade-off: más storage, queries complejas
- Producción: tabla actual + tabla historial separadas"

---

## 📚 Recursos

- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [DynamoDB Best Practices](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/best-practices.html)
- [DAX Documentation](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/DAX.html)

---

## ⭐ Próximos Pasos

- [ ] CI/CD pipeline (GitHub Actions)
- [ ] Tests automatizados (Terratest, Jest)
- [ ] Multi-región deployment
- [ ] Monitoring avanzado (Datadog)
- [ ] API authentication (Cognito)

---

**¿Listo para el deploy?** Sigue la guía paso a paso arriba.

**¡Buena suerte en tu entrevista!** 🎯