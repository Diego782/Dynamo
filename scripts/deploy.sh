#!/bin/bash
# ============================================================================
# DEPLOYMENT HELPER SCRIPT
# ============================================================================
# Script para simplificar el deployment del proyecto
# ============================================================================

set -e  # Exit on error

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Funciones helper
info() {
    echo -e "${BLUE}ℹ ${1}${NC}"
}

success() {
    echo -e "${GREEN}✓ ${1}${NC}"
}

warning() {
    echo -e "${YELLOW}⚠ ${1}${NC}"
}

error() {
    echo -e "${RED}✗ ${1}${NC}"
    exit 1
}

# ============================================================================
# VALIDACIONES
# ============================================================================

check_requirements() {
    info "Verificando requisitos..."
    
    # Terraform
    if ! command -v terraform &> /dev/null; then
        error "Terraform no está instalado. Instalar desde https://www.terraform.io/"
    fi
    success "Terraform encontrado: $(terraform version -json | jq -r '.terraform_version')"
    
    # AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI no está instalado. Instalar desde https://aws.amazon.com/cli/"
    fi
    success "AWS CLI encontrado: $(aws --version)"
    
    # Node.js
    if ! command -v node &> /dev/null; then
        error "Node.js no está instalado. Instalar desde https://nodejs.org/"
    fi
    success "Node.js encontrado: $(node --version)"
    
    # jq (opcional pero útil)
    if ! command -v jq &> /dev/null; then
        warning "jq no está instalado (opcional). Recomendado para testing."
    fi
    
    # Credenciales AWS
    if ! aws sts get-caller-identity &> /dev/null; then
        error "Credenciales de AWS no configuradas. Ejecutar 'aws configure'"
    fi
    success "Credenciales AWS válidas: $(aws sts get-caller-identity --query Account --output text)"
}

# ============================================================================
# BOOTSTRAP
# ============================================================================

bootstrap() {
    info "Ejecutando bootstrap del backend remoto..."
    
    cd terraform/bootstrap
    
    info "Inicializando Terraform..."
    terraform init
    
    info "Planificando..."
    terraform plan -out=tfplan
    
    read -p "¿Aplicar el plan? (yes/no): " CONFIRM
    if [ "$CONFIRM" != "yes" ]; then
        error "Bootstrap cancelado"
    fi
    
    info "Aplicando..."
    terraform apply tfplan
    rm tfplan
    
    success "Bootstrap completado!"
    warning "IMPORTANTE: Copia el output 'backend_config' y actualiza terraform/backend.tf"
    
    terraform output backend_config
    
    read -p "¿Ya actualizaste backend.tf? (yes/no): " CONFIRM
    if [ "$CONFIRM" != "yes" ]; then
        warning "Actualiza terraform/backend.tf antes de continuar"
        exit 0
    fi
    
    cd ../..
}

# ============================================================================
# DEPLOY ENVIRONMENT
# ============================================================================

deploy_env() {
    ENV=$1
    
    if [ -z "$ENV" ]; then
        error "Debe especificar ambiente: dev, staging o prod"
    fi
    
    if [ ! -d "terraform/envs/${ENV}" ]; then
        error "Ambiente '${ENV}' no existe"
    fi
    
    info "Desplegando ambiente: ${ENV}"
    
    # Instalar dependencias de app
    info "Instalando dependencias de Node.js..."
    cd app
    npm install
    cd ..
    
    # Deploy Terraform
    cd terraform/envs/${ENV}
    
    info "Inicializando Terraform..."
    terraform init
    
    info "Validando configuración..."
    terraform validate
    
    info "Formateando código..."
    terraform fmt -recursive
    
    info "Planificando deployment..."
    terraform plan -out=tfplan
    
    read -p "¿Aplicar el plan? (yes/no): " CONFIRM
    if [ "$CONFIRM" != "yes" ]; then
        error "Deployment cancelado"
    fi
    
    warning "DAX cluster tarda ~15-20 minutos en crearse. Por favor espera..."
    
    info "Aplicando..."
    terraform apply tfplan
    rm tfplan
    
    success "Deployment completado!"
    
    # Mostrar outputs importantes
    echo ""
    info "=== OUTPUTS ==="
    terraform output
    
    # Guardar outputs
    terraform output -json > outputs.json
    success "Outputs guardados en outputs.json"
    
    cd ../../..
    
    # Testing básico
    test_deployment ${ENV}
}

# ============================================================================
# TESTING
# ============================================================================

test_deployment() {
    ENV=$1
    
    info "Ejecutando tests básicos..."
    
    cd terraform/envs/${ENV}
    
    API_URL=$(terraform output -raw api_gateway_url 2>/dev/null || echo "")
    
    if [ -z "$API_URL" ]; then
        warning "No se pudo obtener API URL. Verificar outputs."
        cd ../../..
        return
    fi
    
    info "API Gateway URL: ${API_URL}"
    
    # Test 1: Health check básico (crear producto)
    info "Test: Creando producto de prueba..."
    
    RESPONSE=$(curl -s -X POST "${API_URL}/products" \
        -H "Content-Type: application/json" \
        -d '{
            "name": "Test Product",
            "category": "test",
            "price": 9.99,
            "stock": 1
        }')
    
    if echo "$RESPONSE" | grep -q "created successfully"; then
        success "✓ Write test passed"
        
        # Extraer ProductID
        if command -v jq &> /dev/null; then
            PRODUCT_ID=$(echo "$RESPONSE" | jq -r '.product.ProductID')
            
            if [ "$PRODUCT_ID" != "null" ] && [ -n "$PRODUCT_ID" ]; then
                # Test 2: Read test
                info "Test: Leyendo producto..."
                
                READ_RESPONSE=$(curl -s -X GET "${API_URL}/products/${PRODUCT_ID}")
                
                if echo "$READ_RESPONSE" | grep -q "usedDAX"; then
                    success "✓ Read test passed (DAX)"
                else
                    warning "⚠ Read test passed but DAX status unclear"
                fi
                
                # Cleanup
                curl -s -X DELETE "${API_URL}/products/${PRODUCT_ID}" > /dev/null
            fi
        fi
    else
        error "✗ Write test failed: $RESPONSE"
    fi
    
    cd ../../..
    
    success "Tests completados!"
}

# ============================================================================
# DESTROY
# ============================================================================

destroy_env() {
    ENV=$1
    
    if [ -z "$ENV" ]; then
        error "Debe especificar ambiente: dev, staging o prod"
    fi
    
    warning "¡ADVERTENCIA! Esto eliminará TODOS los recursos del ambiente ${ENV}"
    read -p "¿Estás seguro? Escribe 'yes' para confirmar: " CONFIRM
    
    if [ "$CONFIRM" != "yes" ]; then
        info "Operación cancelada"
        exit 0
    fi
    
    cd terraform/envs/${ENV}
    
    info "Destruyendo recursos..."
    terraform destroy
    
    success "Recursos destruidos"
    
    cd ../../..
}

# ============================================================================
# MAIN
# ============================================================================

show_usage() {
    cat << EOF
Uso: ./scripts/deploy.sh <comando> [opciones]

Comandos:
  check           Verificar requisitos
  bootstrap       Ejecutar bootstrap del backend remoto
  deploy <env>    Desplegar ambiente (dev, staging, prod)
  test <env>      Ejecutar tests en ambiente
  destroy <env>   Destruir todos los recursos de un ambiente
  help            Mostrar esta ayuda

Ejemplos:
  ./scripts/deploy.sh check
  ./scripts/deploy.sh bootstrap
  ./scripts/deploy.sh deploy dev
  ./scripts/deploy.sh test dev
  ./scripts/deploy.sh destroy dev

EOF
}

main() {
    COMMAND=$1
    ARG=$2
    
    case $COMMAND in
        check)
            check_requirements
            ;;
        bootstrap)
            check_requirements
            bootstrap
            ;;
        deploy)
            check_requirements
            deploy_env $ARG
            ;;
        test)
            test_deployment $ARG
            ;;
        destroy)
            destroy_env $ARG
            ;;
        help|--help|-h)
            show_usage
            ;;
        *)
            error "Comando desconocido: $COMMAND"
            show_usage
            exit 1
            ;;
    esac
}

# Ejecutar
main "$@"
