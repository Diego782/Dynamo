# Terraform Infrastructure

Este directorio contiene toda la infraestructura como código (IaC) del proyecto.

## 📂 Estructura

```
terraform/
├── bootstrap/          # Backend remoto (ejecutar primero)
├── modules/            # Módulos reutilizables
│   ├── networking/     # VPC, subnets, NAT
│   ├── dynamodb/       # Tabla DynamoDB
│   ├── dax/            # Cluster DAX
│   ├── iam/            # Roles y policies
│   └── lambda/         # Lambda function
├── envs/               # Ambientes
│   ├── dev/            # Desarrollo
│   ├── staging/        # Pre-producción
│   └── prod/           # Producción
└── backend.tf          # Configuración backend

```

## 🚀 Orden de Ejecución

### 1. Bootstrap (Una sola vez)
```bash
cd bootstrap/
terraform init
terraform apply
```

### 2. Configurar Backend
Editar `backend.tf` y descomentar el bloque backend "s3"

### 3. Deploy Ambiente
```bash
cd envs/dev/
terraform init
terraform apply
```

## 📋 Módulos

### networking
Crea VPC completa con:
- Subnets públicas y privadas
- NAT Gateways (configurable 1 o múltiples)
- Internet Gateway
- Route Tables
- VPC Endpoints (DynamoDB)
- Flow Logs (opcional)

**Inputs clave:**
- `vpc_cidr`: CIDR de la VPC
- `availability_zones`: Lista de AZs
- `single_nat_gateway`: true en dev, false en prod

### dynamodb
Crea tabla DynamoDB con:
- Partition Key + Sort Key
- Global Secondary Indexes (GSI)
- Point-In-Time Recovery (PITR)
- TTL
- Streams (opcional)
- Auto-scaling (provisioned mode)
- CloudWatch Alarms

**Inputs clave:**
- `table_name`: Nombre de la tabla
- `billing_mode`: PAY_PER_REQUEST o PROVISIONED
- `global_secondary_indexes`: Lista de GSIs

### dax
Crea cluster DAX con:
- Subnet group en subnets privadas
- Parameter group (TTL config)
- Security groups
- CloudWatch Alarms

**Inputs clave:**
- `cluster_name`: Nombre del cluster
- `node_type`: dax.t3.small, dax.r5.large, etc.
- `replication_factor`: Número de nodos (1-10)

### iam
Crea roles IAM:
- DAX service role
- Lambda execution role
- EC2 instance role (opcional)

**Principio:** Least privilege, recursos específicos

### lambda
Crea Lambda function:
- Package desde source_dir
- VPC configuration
- Environment variables
- CloudWatch Logs
- API Gateway permissions

## 🔧 Variables por Ambiente

| Variable | Dev | Staging | Prod |
|----------|-----|---------|------|
| VPC CIDR | 10.0.0.0/16 | 10.1.0.0/16 | 10.2.0.0/16 |
| AZs | 2 | 2 | 3 |
| NAT Gateways | 1 | 2 | 3 |
| DAX Nodes | 1 | 2 | 3 |
| DAX Type | t3.small | t3.medium | r5.large |
| Flow Logs | No | Sí | Sí |
| Alarms | No | Sí | Sí |

## 💡 Tips

### Formateo
```bash
terraform fmt -recursive
```

### Validación
```bash
terraform validate
```

### Plan sin apply
```bash
terraform plan -out=tfplan
```

### Aplicar plan guardado
```bash
terraform apply tfplan
```

### Ver state
```bash
terraform state list
terraform state show <resource>
```

### Imports
```bash
terraform import <resource_type>.<name> <aws_id>
```

### Refresh
```bash
terraform refresh
```

## 🔒 Seguridad

### State File
- ✅ Almacenado en S3 encriptado
- ✅ Versionado habilitado
- ✅ Locking con DynamoDB
- ⚠️ NUNCA commitear .tfstate a Git

### Variables Sensibles
```hcl
variable "secret" {
  type      = string
  sensitive = true
}
```

### Providers Versionados
Siempre especificar versión:
```hcl
required_providers {
  aws = {
    source  = "hashicorp/aws"
    version = "~> 5.0"
  }
}
```

## 🐛 Troubleshooting

### Error: State locked
```bash
terraform force-unlock <LOCK_ID>
```

### Error: No provider
```bash
terraform init -upgrade
```

### Drift detection
```bash
terraform plan -refresh-only
```

## 📚 Documentación

- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [Terraform Best Practices](https://www.terraform-best-practices.com/)
- [AWS Well-Architected](https://aws.amazon.com/architecture/well-architected/)

---

**Para deployment completo ver:** [../docs/QUICKSTART.md](../docs/QUICKSTART.md)
