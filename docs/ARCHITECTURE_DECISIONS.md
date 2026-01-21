# 🎨 Architecture Decision Records (ADR)

Este documento registra las decisiones arquitectónicas importantes tomadas en el proyecto, sus justificaciones y alternativas consideradas.

---

## ADR-001: Backend Remoto con S3 + DynamoDB

**Fecha:** 2026-01-21  
**Estado:** ✅ Aceptado  
**Contexto:** Necesitamos almacenar el state de Terraform de manera segura y colaborativa

### Decisión
Usar S3 para almacenar el state file y DynamoDB para locking

### Alternativas Consideradas

| Opción | Pros | Contras | Decisión |
|--------|------|---------|----------|
| **Backend local** | Simple, sin costos | No colaborativo, riesgo de pérdida | ❌ Rechazado |
| **S3 + DynamoDB** | Seguro, versionado, locking | Costo mínimo ($0.27/mes) | ✅ Seleccionado |
| **Terraform Cloud** | Managed, features adicionales | Costo mayor, vendor lock-in | ❌ No necesario |
| **GitLab/GitHub** | Integrado con CI/CD | Requiere configuración compleja | 🟡 Futuro |

### Consecuencias
- ✅ State compartido entre equipo
- ✅ Locking previene race conditions
- ✅ Versionado permite rollback
- ❌ Dependencia de AWS para terraform operations

---

## ADR-002: DynamoDB On-Demand vs Provisioned

**Fecha:** 2026-01-21  
**Estado:** ✅ Aceptado (dev/staging), 🟡 Reevaluar (prod)  
**Contexto:** Elegir billing mode para DynamoDB

### Decisión
Usar PAY_PER_REQUEST (on-demand) por defecto

### Comparación

| Aspecto | On-Demand | Provisioned |
|---------|-----------|-------------|
| **Planning** | ❌ No requiere | ✅ Requiere forecasting |
| **Auto-scaling** | ✅ Automático | 🟡 Manual con auto-scaling |
| **Costo fijo** | ❌ No predecible | ✅ Predecible |
| **Costo variable** | ❌ Más caro (tráfico alto) | ✅ Más barato (tráfico constante) |
| **Throttling** | ❌ Raro | ✅ Posible si se excede |

### Decisión Final
- **Dev/Staging:** On-Demand (simplicidad)
- **Prod:** Evaluar con datos reales de tráfico

### Umbral de Decisión
Cambiar a provisioned si:
- Tráfico > 100K RCU/día constante
- Patrón de tráfico predecible
- Costo on-demand > costo provisioned + 20%

---

## ADR-003: DAX Node Type Selection

**Fecha:** 2026-01-21  
**Estado:** ✅ Aceptado  
**Contexto:** Seleccionar tipo de nodo para DAX cluster

### Decisión
Usar diferentes node types por ambiente

### Configuración

| Ambiente | Node Type | Nodes | RAM | vCPU | Costo/mes |
|----------|-----------|-------|-----|------|-----------|
| **Dev** | dax.t3.small | 1 | 1.5GB | 2 | ~$29 |
| **Staging** | dax.t3.medium | 2 | 3GB | 2 | ~$115 |
| **Prod** | dax.r5.large | 3 | 16GB | 2 | ~$612 |

### Criterios de Decisión

**dax.t3.small (Dev):**
- ✅ Suficiente para testing
- ✅ Costo bajo
- ❌ No para carga real

**dax.r5.large (Prod):**
- ✅ 16GB RAM (working set grande)
- ✅ Performance predecible
- ❌ Costo alto

### Cuándo Escalar
- CPU > 75% sostenido → Vertical scaling (node type mayor)
- EvictedSize alto → Working set no cabe en memoria
- Cache miss rate alto → Más nodos (horizontal scaling)

---

## ADR-004: Lambda en VPC

**Fecha:** 2026-01-21  
**Estado:** ✅ Aceptado  
**Contexto:** Lambda necesita acceder a DAX en subnets privadas

### Decisión
Colocar Lambda en VPC (subnets privadas)

### Trade-offs

| Aspecto | Sin VPC | Con VPC |
|---------|---------|---------|
| **Acceso a DAX** | ❌ No posible | ✅ Posible |
| **Cold start** | ✅ Rápido (~1s) | ❌ Más lento (~2-3s) |
| **Networking** | ✅ Simple | ❌ Requiere NAT Gateway |
| **Seguridad** | 🟡 Público | ✅ Privado |
| **Costo** | ✅ Solo Lambda | ❌ + NAT Gateway |

### Mitigaciones Cold Start
1. Provisioned Concurrency (dev: no, prod: considerar)
2. Keep-warm strategy (ping cada 5 min)
3. Minimizar tamaño del package
4. Usar compiled languages (alternativa)

### Alternativa Rechazada
**DAX público con VPN/TLS:**
- ❌ DAX no soporta deployment público
- ❌ Más complejo
- ❌ Peor seguridad

---

## ADR-005: API Gateway HTTP API vs REST API

**Fecha:** 2026-01-21  
**Estado:** ✅ Aceptado  
**Contexto:** Elegir tipo de API Gateway

### Decisión
Usar HTTP API (v2)

### Comparación

| Feature | HTTP API | REST API |
|---------|----------|----------|
| **Precio** | ✅ $1/M requests | ❌ $3.50/M |
| **Latencia** | ✅ Menor (~60%) | 🟡 Mayor |
| **WebSocket** | ✅ Soportado | ❌ No |
| **API Keys** | ❌ No | ✅ Sí |
| **Usage Plans** | ❌ No | ✅ Sí |
| **Request Validation** | 🟡 Básica | ✅ Avanzada |
| **CORS** | ✅ Nativo | 🟡 Manual |

### Cuándo Usar REST API
- Necesitas API keys / usage plans
- Request/response transformation compleja
- WAF integration crítico
- Validación de schema avanzada

### Nuestro Caso
✅ HTTP API suficiente:
- CORS simple
- Lambda proxy integration
- Sin necesidad de API keys (por ahora)
- Costo optimizado

---

## ADR-006: Separation of Write/Read Clients

**Fecha:** 2026-01-21  
**Estado:** ✅ Aceptado  
**Contexto:** Cómo integrar DAX con DynamoDB en la aplicación

### Decisión
Separar clientes: writes → DynamoDB, reads → DAX

### Patrón Implementado

```javascript
// Writes
const writeClient = getWriteClient();  // → DynamoDB directo
await writeClient.put({ ... });

// Reads
const readClient = getReadClient();    // → DAX → DynamoDB
await readClient.get({ ... });
```

### Justificación

**¿Por qué writes NO van a DAX?**
1. DAX es write-through (agrega latencia)
2. Writes son menos frecuentes (no necesitan cache)
3. Strong consistency en writes

**¿Por qué reads SÍ van a DAX?**
1. Cache reduce latencia ~90% (10ms → 1ms)
2. Reduce RCUs de DynamoDB
3. Eventual consistency aceptable

### Alternativas

| Opción | Resultado |
|--------|-----------|
| Todo via DAX | ❌ Writes lentos innecesariamente |
| Todo via DynamoDB | ❌ No usa DAX, latencia alta |
| **Separación CQRS** | ✅ Best of both worlds |

---

## ADR-007: Multi-NAT Gateway Strategy

**Fecha:** 2026-01-21  
**Estado:** ✅ Aceptado  
**Contexto:** Alta disponibilidad vs costo

### Decisión
NAT Gateways según ambiente:
- Dev: 1 NAT
- Staging: 2 NAT  
- Prod: 3 NAT (una por AZ)

### Cost-Availability Trade-off

```
┌──────────────┬────────────┬────────────────┐
│ NAT Gateways │ Costo/mes  │ Disponibilidad │
├──────────────┼────────────┼────────────────┤
│ 1 (dev)      │ $32        │ 99.5%          │
│ 2 (staging)  │ $64        │ 99.9%          │
│ 3 (prod)     │ $96        │ 99.99%         │
└──────────────┴────────────┴────────────────┘
```

### Escenario de Falla

**1 NAT:**
- AZ con NAT falla → Sin conectividad para recursos privados
- RTO: ~5 min (recrear NAT)

**3 NAT:**
- AZ con NAT falla → Otros AZs siguen funcionando
- RTO: 0s (transparent failover)

### Optimización
En dev, aceptamos single point of failure por:
- ✅ Costo 66% menor
- ✅ No critical workloads
- ✅ Downtime aceptable

---

## ADR-008: TTL Implementation

**Fecha:** 2026-01-21  
**Estado:** ✅ Aceptado  
**Contexto:** Limpieza automática de datos temporales

### Decisión
Habilitar TTL con atributo `ExpiresAt`

### Use Cases

| Dato | TTL | Razón |
|------|-----|-------|
| Sesiones | 24h | Expiran naturalmente |
| Cache entries | 1h | Datos temporales |
| Test data | 30d | Cleanup automático |
| Productos | Opcional | Depende del negocio |

### Implementación

```javascript
{
  ProductID: "uuid",
  ExpiresAt: Math.floor(Date.now() / 1000) + (30 * 24 * 60 * 60),  // +30 días
  ...
}
```

### Beneficios
- ✅ Cleanup automático (gratis)
- ✅ Sin Lambda triggers necesarios
- ✅ Reduce storage costs
- ❌ Eventually consistent (hasta 48h delay)

### Alternativa Rechazada
**Lambda + EventBridge para cleanup:**
- ❌ Más complejo
- ❌ Costo adicional
- ✅ Control exacto del timing
- **Decisión:** TTL suficiente para nuestro caso

---

## ADR-009: CloudWatch Alarms Strategy

**Fecha:** 2026-01-21  
**Estado:** ✅ Aceptado  
**Contexto:** Observabilidad sin noise

### Decisión
Alarmas solo en staging/prod, no en dev

### Alarmas Implementadas

**DynamoDB:**
- ReadThrottleEvents > 10 (5 min)
- WriteThrottleEvents > 10 (5 min)

**DAX:**
- CPUUtilization > 75% (5 min)
- ItemCacheMisses > 1000 (5 min)
- EvictedSize > 1MB (5 min)

### Por qué NO en dev
- ❌ Ruido innecesario
- ❌ Costo de alarmas (~$0.10/mes cada una)
- ❌ Desarrolladores experimentando con cargas

### Futuro: SNS Topics
```hcl
# En staging/prod
resource "aws_sns_topic" "alerts" {
  name = "${var.project}-alerts"
}

# Subscribir a:
# - Email del equipo
# - Slack webhook
# - PagerDuty
```

---

## ADR-010: Module Design Philosophy

**Fecha:** 2026-01-21  
**Estado:** ✅ Aceptado  
**Contexto:** Estructura de módulos Terraform

### Decisión
Módulos pequeños, single-responsibility, composables

### Principios

**1. Single Responsibility**
```
✅ modules/dynamodb/     (solo tabla)
✅ modules/dax/          (solo cluster)
❌ modules/database/     (dynamodb + dax + rds)
```

**2. Minimal Coupling**
```hcl
# Módulo no debe conocer detalles de otros
# Comunicación via outputs
```

**3. Reusable Across Environments**
```hcl
module "dynamodb" {
  source = "../../modules/dynamodb"
  
  # Variables específicas del ambiente
  table_name   = "${var.env}-products"
  billing_mode = var.env == "prod" ? "PROVISIONED" : "PAY_PER_REQUEST"
}
```

### Estructura de Módulo

```
module/
├── main.tf       # Recursos principales
├── variables.tf  # Inputs
├── outputs.tf    # Outputs
└── README.md     # Documentación (opcional)
```

### Alternativa Rechazada
**Módulos monolíticos:**
- ❌ Difícil de testear
- ❌ Coupling alto
- ❌ Menos reutilizables

---

## 📊 Resumen de Decisiones

| ADR | Decisión | Impacto | Costo |
|-----|----------|---------|-------|
| 001 | Backend S3 + DynamoDB | 🟢 Alto | 💰 Bajo |
| 002 | DynamoDB On-Demand | 🟡 Medio | 💰 Medio |
| 003 | DAX Node Types | 🟢 Alto | 💰💰 Alto |
| 004 | Lambda en VPC | 🟢 Alto | 💰 Medio |
| 005 | HTTP API | 🟢 Medio | 💰 Bajo |
| 006 | CQRS Pattern | 🟢 Alto | 💰 Ninguno |
| 007 | Multi-NAT | 🟡 Medio | 💰💰 Alto |
| 008 | TTL | 🟡 Bajo | 💰 Ninguno |
| 009 | Alarmas | 🟢 Medio | 💰 Bajo |
| 010 | Módulos | 🟢 Alto | 💰 Ninguno |

---

## 🔄 Proceso de ADR

1. **Identificar decisión** importante (afecta arquitectura/costo/seguridad)
2. **Documentar contexto** y problema
3. **Listar alternativas** con pros/contras
4. **Tomar decisión** con justificación
5. **Documentar consecuencias**
6. **Revisar periódicamente** (cada 3-6 meses)

---

**Última actualización:** Enero 2026
