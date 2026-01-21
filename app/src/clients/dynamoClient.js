// ============================================================================
// DYNAMODB CLIENT FACTORY
// ============================================================================
// Este módulo crea clientes de DynamoDB con o sin DAX
//
// ARQUITECTURA:
// =============
// - WRITES: Siempre van directo a DynamoDB (sin DAX)
// - READS: Van a DAX si está configurado, sino a DynamoDB
//
// ¿POR QUÉ DAX SOLO PARA LECTURAS?
// ================================
// DAX es un write-through cache:
// 1. Los writes deben ir directo a DynamoDB
// 2. DAX invalida su cache automáticamente cuando detecta cambios
// 3. Si escribes vía DAX, funciona, pero agrega latencia innecesaria
//
// TRADE-OFFS:
// ===========
// ✅ PRO: Lectura ~1ms (vs ~10ms DynamoDB)
// ✅ PRO: Reduce RCUs de DynamoDB
// ❌ CON: Eventual consistency (cache puede estar stale)
// ❌ CON: No funciona con todas las operaciones (e.g., transacciones)
// ============================================================================

const AWS = require('aws-sdk');

// Lazy-loaded DAX client (solo si DAX_ENDPOINT está configurado)
let AmazonDaxClient;

/**
 * Crea cliente de DynamoDB directo (sin DAX)
 * Usado para: WRITES, transacciones, operaciones que DAX no soporta
 */
function createDynamoDBClient() {
  return new AWS.DynamoDB.DocumentClient({
    region: process.env.AWS_REGION || 'us-east-1',
    // Configuración adicional si es necesario
    maxRetries: 3,
    httpOptions: {
      timeout: 5000,
      connectTimeout: 3000
    }
  });
}

/**
 * Crea cliente DAX (si está disponible)
 * Usado para: READS de alta frecuencia
 * 
 * NOTA: DAX client requiere amazon-dax-client npm package
 * Si el endpoint no está configurado, retorna cliente DynamoDB normal
 */
function createDAXClient() {
  const daxEndpoint = process.env.DAX_ENDPOINT;
  
  if (!daxEndpoint) {
    console.log('DAX_ENDPOINT not configured, falling back to DynamoDB');
    return createDynamoDBClient();
  }

  try {
    // Lazy load para evitar error si el package no está instalado
    if (!AmazonDaxClient) {
      AmazonDaxClient = require('amazon-dax-client');
    }

    const dax = new AmazonDaxClient({
      endpoints: [daxEndpoint],
      region: process.env.AWS_REGION || 'us-east-1',
      // Configuración de conexión
      requestTimeout: 5000,
      // DAX usa connection pooling
      maxSockets: 50
    });

    console.log(`DAX client configured with endpoint: ${daxEndpoint}`);
    
    return new AWS.DynamoDB.DocumentClient({ service: dax });
  } catch (error) {
    console.error('Error creating DAX client, falling back to DynamoDB:', error.message);
    return createDynamoDBClient();
  }
}

// ============================================================================
// SINGLETON CLIENTS
// ============================================================================
// Reutilizar clientes entre invocaciones de Lambda (warm start optimization)

let dynamoDBClient;
let daxClient;

/**
 * Obtiene cliente para writes (siempre DynamoDB directo)
 */
function getWriteClient() {
  if (!dynamoDBClient) {
    dynamoDBClient = createDynamoDBClient();
  }
  return dynamoDBClient;
}

/**
 * Obtiene cliente para reads (DAX si está disponible)
 */
function getReadClient() {
  if (!daxClient) {
    daxClient = createDAXClient();
  }
  return daxClient;
}

/**
 * Verifica si estamos usando DAX
 */
function isUsingDAX() {
  return !!process.env.DAX_ENDPOINT;
}

module.exports = {
  getWriteClient,
  getReadClient,
  isUsingDAX,
  // Exportar para testing
  createDynamoDBClient,
  createDAXClient
};

// ============================================================================
// ¿QUÉ DIRÍA UN SENIOR EN UNA ENTREVISTA?
// ============================================================================
// "Separamos conceptualmente los clientes de lectura y escritura. Los writes
// siempre van directo a DynamoDB porque DAX no agrega valor ahí (de hecho,
// agrega latencia). Los reads usan DAX cuando está disponible.
//
// El cliente DAX usa el mismo API que DocumentClient, entonces el código
// de negocio no necesita cambios. Es una optimización transparente.
//
// Implementamos lazy loading y singleton pattern para reutilizar conexiones
// entre invocaciones Lambda (warm start optimization).
//
// En producción, monitoreamos:
// 1. Métricas de DAX (cache hit rate, miss rate)
// 2. Latencias de lectura (CloudWatch Logs Insights)
// 3. Errores de conexión a DAX
//
// Si DAX falla, el código automáticamente hace fallback a DynamoDB.
// Es importante que DAX sea opcional, no un single point of failure."
// ============================================================================
