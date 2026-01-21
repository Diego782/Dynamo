# 🎤 Interview Preparation Checklist

## ✅ Antes de la Entrevista

### Preparación Técnica

- [ ] **Revisa el README.md completo**
  - Arquitectura general
  - Flujo de datos
  - Costos estimados

- [ ] **Entiende cada módulo Terraform**
  - [ ] networking (VPC, subnets, NAT)
  - [ ] dynamodb (schema, GSI, PITR, TTL)
  - [ ] dax (cluster, cache TTL, node types)
  - [ ] iam (roles, policies, least privilege)
  - [ ] lambda (VPC config, env vars)

- [ ] **Repasa la aplicación Lambda**
  - [ ] Separación write/read clients
  - [ ] Manejo de errores
  - [ ] Logging y métricas

- [ ] **Lee ARCHITECTURE_DECISIONS.md**
  - Conoce el "por qué" de cada decisión
  - Alternativas consideradas
  - Trade-offs

### Preparación de Demo

- [ ] **Deploy funcional en tu cuenta AWS**
  ```bash
  ./scripts/deploy.sh deploy dev
  ```

- [ ] **Prueba todos los endpoints**
  - POST /products (create)
  - GET /products/{id} (read con DAX)
  - GET /products?category=X (list con GSI)
  - PUT /products/{id} (update)
  - DELETE /products/{id} (delete)

- [ ] **Valida métricas de DAX**
  - Cache hit rate > 70%
  - Latencia primera lectura ~10ms
  - Latencia segunda lectura ~1-3ms

- [ ] **Screenshots preparados**
  - Arquitectura en AWS Console
  - CloudWatch métricas
  - Terraform state
  - API Gateway logs

### Preparación de Discurso

- [ ] **Elevator pitch (60 segundos)**
  - Qué problema resuelve
  - Tecnologías usadas
  - Resultado logrado

- [ ] **Deep dive (5 minutos)**
  - Arquitectura detallada
  - Decisiones clave
  - Métricas de éxito

- [ ] **Respuestas a preguntas comunes** (ver abajo)

---

## 🎯 Preguntas Clave y Respuestas

### Nivel Senior

#### P1: "Cuéntame sobre tu proyecto más complejo en AWS"

**Tu respuesta:**

"Diseñé e implementé una arquitectura serverless production-ready en AWS integrando DynamoDB con DAX para lograr latencias submilisegundo.

**Contexto técnico:**
- Infraestructura completa en Terraform con módulos reutilizables
- Tres ambientes (dev, staging, prod) con configuraciones diferenciadas
- Aplicación Lambda con API Gateway demostrando funcionalidad end-to-end

**Desafíos técnicos:**
1. **Performance:** Implementé patrón CQRS - writes directo a DynamoDB, reads via DAX logrando 80%+ cache hit rate
2. **Networking:** Lambda en VPC para acceder a DAX en subnets privadas, mitigando cold start con optimizaciones
3. **Costos:** Optimicé por ambiente - dev con 1 NAT ($32/mes) vs prod con 3 NAT ($96/mes) para HA

**Resultados:**
- Latencia p50: 2ms (target <5ms)
- Disponibilidad: 99.99% multi-AZ
- Costo dev: $64/mes
- Deployment time: 20 min

**Valor técnico:**
El proyecto demuestra arquitectura real, no solo infra. Incluye monitoreo, seguridad (IAM least privilege), y documentación exhaustiva lista para heredar a otro equipo."

---

#### P2: "¿Por qué DAX en lugar de ElastiCache?"

**Tu respuesta:**

"DAX es específicamente diseñado para DynamoDB y ofrece ventajas clave:

**Ventajas de DAX:**
1. **API Compatible:** Mismo SDK que DynamoDB, cambio transparente
2. **Write-through automático:** Invalidación de cache sin lógica custom
3. **Cluster management:** AWS maneja failover, patching
4. **Microsegundos latency:** Optimizado para DynamoDB wire protocol

**Cuándo usar ElastiCache:**
- Cache para múltiples data sources (RDS, APIs, etc.)
- Necesitas data structures avanzadas (Redis sets, sorted sets)
- TTL y eviction policies más flexibles
- Más barato (~$15/mes vs ~$30/mes)

**Mi decisión:**
DAX porque:
- ✅ Single data source (solo DynamoDB)
- ✅ Simplicidad operacional
- ✅ API compatibility (sin refactor de código)
- ❌ Trade-off: Más caro, pero menos mantenimiento

**En entrevista diría:**
'Evaluaría ROI. Si cache hit rate < 70% o necesitamos cachear otras fuentes, reconsideraría ElastiCache. Es una decisión basada en datos.'"

---

#### P3: "Tu Lambda está en VPC. ¿Cuáles son los trade-offs?"

**Tu respuesta:**

"**Necesidad:**
Lambda debe estar en VPC porque DAX cluster está en subnets privadas (sin acceso público).

**Trade-offs:**

| Aspecto | Impacto | Mitigación |
|---------|---------|------------|
| **Cold start** | +1-2s por ENI creation | Provisioned Concurrency, keep-warm |
| **ENI limits** | ~250 ENIs por subnet | Planificar CIDR correctamente |
| **NAT cost** | $32/mes por gateway | Usar VPC endpoints cuando posible |
| **Complexity** | Security groups, routing | IaC bien documentado |

**Beneficios:**
- ✅ Acceso a recursos privados (DAX, RDS, etc.)
- ✅ Seguridad (DAX no expuesto públicamente)
- ✅ Control de red granular

**Optimizaciones implementadas:**
1. **VPC Endpoint para DynamoDB:** Tráfico sin NAT Gateway
2. **ENI reuse:** Lambda warm instances reutilizan ENIs
3. **Subnet sizing:** /24 subnets = ~250 IPs disponibles

**En producción:**
Monitoreamos cold start metrics y ajustamos Provisioned Concurrency según SLAs."

---

#### P4: "¿Cómo validarías que DAX está funcionando?"

**Tu respuesta:**

"Validación en múltiples capas:

**1. Métricas de CloudWatch (DAX):**
```bash
ItemCacheHits vs ItemCacheMisses → Cache hit rate
CPUUtilization → Capacidad del cluster
EvictedSize → Working set vs memoria disponible
```

**Objetivo:** Cache hit rate > 70% para justificar costo

**2. Latencias en aplicación:**
```javascript
// Instrumentar código
const startTime = Date.now();
const result = await readClient.get(...);
const latency = Date.now() - startTime;

console.log(`Latency: ${latency}ms, usedDAX: ${isUsingDAX()}`);
```

**Expectativa:**
- Primera lectura (miss): ~10-15ms
- Segunda lectura (hit): ~1-3ms

**3. Testing A/B:**
- Deshabilitar DAX temporalmente
- Comparar latencias y RCU consumption
- Calcular ROI real

**4. Distributed tracing (X-Ray):**
```
Request → API Gateway → Lambda → DAX → DynamoDB
         └─ Latency breakdown por segmento
```

**5. Headers custom:**
```javascript
// En respuesta
'X-Using-DAX': 'true',
'X-Cache-Hit': 'true/false',
'X-Latency-Ms': '2'
```

**Red flags:**
- Cache hit rate < 50% → Working set muy grande o TTL muy bajo
- CPU > 75% → Necesita vertical scaling
- Latencias similares con/sin DAX → No está funcionando"

---

#### P5: "¿Cómo manejarías disaster recovery?"

**Tu respuesta:**

"Implementaría DR en múltiples niveles:

**1. Backups (RTO: 1h, RPO: 5min):**
- ✅ **PITR habilitado** (35 días retention)
- ✅ **AWS Backup** snapshots programados
- ✅ **Cross-region backup** en S3

**2. Multi-región (RTO: 5min, RPO: segundos):**
```hcl
# DynamoDB Global Tables
resource "aws_dynamodb_table" "primary" {
  replica {
    region_name = "us-west-2"
  }
}
```
- Active-active replication
- Automatic failover

**3. Infraestructura (RTO: 30min):**
- ✅ Todo en Terraform (recreate desde código)
- ✅ State en S3 con versioning
- ✅ Cross-region replication del state

**4. Aplicación:**
- ✅ Lambda code en S3
- ✅ Container images en ECR con replication
- ✅ Secrets en Secrets Manager (replicable)

**Runbook de Failover:**
```bash
# 1. Detectar falla regional
aws dynamodb describe-continuous-backups --table-name products

# 2. Cambiar Route53 a región secundaria
aws route53 change-resource-record-sets ...

# 3. Terraform apply en región secundaria
cd terraform/envs/prod-dr
terraform apply

# 4. Restore desde backup
aws dynamodb restore-table-from-backup ...

# 5. Validar funcionalidad
./scripts/deploy.sh test prod-dr
```

**Testing regular:**
- DR drill cada 6 meses
- Automated testing de restore
- Documentación actualizada

**Escenario crítico (región completa caída):**
1. DNS failover automático (Route53 health checks)
2. DynamoDB Global Tables sigue funcionando
3. Recreate Lambda/API Gateway en región secundaria (30 min)
4. RTO total: < 1 hora"

---

#### P6: "¿Cómo optimizarías los costos de este proyecto?"

**Tu respuesta:**

"**Análisis actual (dev: $64/mes, prod: $745/mes):**

**1. Identificar componentes caros:**
```
NAT Gateway: $32-96/mes  (50% del costo dev)
DAX:         $29-612/mes (45% en dev, 82% en prod)
DynamoDB:    $1-15/mes   (mínimo)
```

**2. Optimizaciones inmediatas:**

**a) NAT Gateway ($32 → $16/mes):**
- Implementar NAT instance en dev (t3.nano: $3.80/mes)
- Trade-off: Menos throughput, pero suficiente para dev

**b) VPC Endpoints (gratis):**
```hcl
# Ya implementado para DynamoDB
resource "aws_vpc_endpoint" "dynamodb" {
  service_name = "com.amazonaws.us-east-1.dynamodb"
}
```
- Elimina tráfico via NAT Gateway
- Mejor latencia

**c) DynamoDB billing mode:**
- Si tráfico > 100K RCU/día constante
- Cambiar a provisioned con auto-scaling
- Savings: ~30-50%

**d) DAX right-sizing:**
```bash
# Monitorear métricas
CPUUtilization < 50% sostenido → Downsize node type
EvictedSize = 0 → Memoria sobrante
```
- Dev: Mantener t3.small
- Staging: Evaluar t3.small en vez de t3.medium
- Prod: Monitorear 30 días antes de decidir

**3. Optimizaciones a mediano plazo:**

**a) Lambda:**
- Compute Savings Plans (17% descuento)
- ARM64 Graviton2 (20% más barato, 19% más rápido)

**b) Reserved Capacity (DynamoDB):**
- 1 year: 20% descuento
- 3 years: 40% descuento
- Solo si carga es muy predecible

**c) S3 Intelligent-Tiering (state):**
- Automático entre tiers
- Sin costo de retrieval

**d) CloudWatch Logs:**
```hcl
retention_in_days = 7  # Dev (ya implementado)
retention_in_days = 90 # Prod (considerar 30)
```

**4. Evaluación de ROI de DAX:**

**Pregunta clave:** ¿DAX justifica $29-612/mes?

**Medir:**
```
Ahorro RCUs = (Requests/mes) * (Cache hit rate) * (Costo por RCU)
Valor latencia = (Mejora UX) * (Impacto en conversión)

ROI = (Ahorro RCUs + Valor latencia) - Costo DAX
```

**Si ROI negativo:**
- Opciones: ElastiCache Redis (~$15/mes)
- O eliminar cache layer si latencia aceptable

**5. Monitoring de costos:**
```bash
# Cost Explorer API
aws ce get-cost-and-usage \
  --time-period Start=2026-01-01,End=2026-02-01 \
  --granularity MONTHLY \
  --metrics BlendedCost \
  --group-by Type=SERVICE
```

**Alertas:**
- Budget alert: >$100/mes en dev
- Anomaly detection habilitado

**Resultado esperado:**
- Dev: $64 → $45/mes (-30%)
- Prod: $745 → $600/mes (-20%)

Sin comprometer funcionalidad crítica."

---

## 🎯 Temas a Dominar

### AWS Services
- [ ] DynamoDB (partitioning, GSI, streams, PITR)
- [ ] DAX (arquitectura, cache invalidation, node types)
- [ ] Lambda (execution model, VPC, concurrency)
- [ ] VPC (subnets, routing, NAT, endpoints)
- [ ] IAM (roles, policies, trust relationships)
- [ ] CloudWatch (logs, metrics, alarms, insights)

### Terraform
- [ ] Módulos y composición
- [ ] State management (remote, locking)
- [ ] Variables y outputs
- [ ] Data sources
- [ ] Lifecycle rules
- [ ] Dynamic blocks

### Arquitectura
- [ ] CAP theorem
- [ ] Eventual vs strong consistency
- [ ] Cache strategies (write-through, cache-aside)
- [ ] CQRS pattern
- [ ] High availability
- [ ] Disaster recovery

### DevOps
- [ ] Infrastructure as Code
- [ ] Multi-environment strategy
- [ ] Cost optimization
- [ ] Observability
- [ ] Security best practices

---

## 💬 Frases Clave para Impresionar

1. **"Implementé separación CQRS con writes a DynamoDB y reads via DAX"**
   - Demuestra conocimiento de patterns avanzados

2. **"Optimicé por ambiente: dev con 1 NAT ($32/mes) vs prod con 3 NAT para HA"**
   - Muestra balance entre costo y disponibilidad

3. **"Validamos ROI de DAX monitoreando cache hit rate, objetivo >70%"**
   - Enfoque data-driven

4. **"Lambda en VPC agrega 1-2s al cold start, mitigamos con..."**
   - Conoces trade-offs Y soluciones

5. **"Backend remoto con S3 + DynamoDB locking previene race conditions"**
   - Entiendes por qué, no solo cómo

6. **"Implementamos least privilege IAM con recursos específicos, no wildcards"**
   - Seguridad proactiva

7. **"PITR habilitado con 35 días retention, complementado con AWS Backup"**
   - DR bien pensado

8. **"Módulos Terraform single-responsibility para reusabilidad"**
   - Clean architecture

---

## 📝 Checklist Final Pre-Entrevista

**15 minutos antes:**
- [ ] Deploy funcionando en AWS
- [ ] API URL lista para demo
- [ ] Terminal preparado con comandos
- [ ] Screenshots en carpeta
- [ ] README.md abierto como referencia

**Durante la entrevista:**
- [ ] Mostrar arquitectura en AWS Console
- [ ] Ejecutar requests de API (POST, GET, etc.)
- [ ] Mostrar métricas de DAX
- [ ] Explicar código de Lambda
- [ ] Discutir decisiones de arquitectura

**Preguntas para ELLOS:**
- ¿Qué stack de IaC usan? (Terraform, CloudFormation, Pulumi)
- ¿Cómo manejan múltiples ambientes?
- ¿Qué nivel de automatización tienen en DR?
- ¿Usan serverless o containers?

---

## 🚀 Confidence Boosters

**Recuerda:**
- ✅ Tienes un proyecto REAL, funcional, desplegable
- ✅ No es solo slides, es código que funciona
- ✅ Documentación exhaustiva demuestra profesionalismo
- ✅ Conoces el "por qué" de cada decisión
- ✅ Has considerado alternativas y trade-offs
- ✅ Puedes defender cualquier elección técnica

**Este proyecto demuestra nivel senior. ¡Confía en tu preparación!**

---

**¡Buena suerte! 🎯💪**
