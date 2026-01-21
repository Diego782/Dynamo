// ============================================================================
// PRODUCT HANDLER - Lambda Functions
// ============================================================================
// Implementa operaciones CRUD sobre productos en DynamoDB
//
// ENDPOINTS:
// ==========
// POST   /products       → createProduct   (write → DynamoDB)
// GET    /products/:id   → getProduct      (read → DAX → DynamoDB)
// PUT    /products/:id   → updateProduct   (write → DynamoDB)
// DELETE /products/:id   → deleteProduct   (write → DynamoDB)
// GET    /products       → listProducts    (read → DAX → DynamoDB)
//
// ARQUITECTURA:
// =============
// - WRITES: Van directo a DynamoDB (sin DAX)
// - READS: Van a DAX, que cachea y forwardea a DynamoDB si miss
// ============================================================================

const { getWriteClient, getReadClient, isUsingDAX } = require('../clients/dynamoClient');
const { v4: uuidv4 } = require('uuid');

const TABLE_NAME = process.env.TABLE_NAME;

// ============================================================================
// HELPER FUNCTIONS
// ============================================================================

/**
 * Crea respuesta HTTP consistente
 */
function createResponse(statusCode, body, additionalHeaders = {}) {
  return {
    statusCode,
    headers: {
      'Content-Type': 'application/json',
      'Access-Control-Allow-Origin': '*',
      'X-Using-DAX': isUsingDAX() ? 'true' : 'false',
      ...additionalHeaders
    },
    body: JSON.stringify(body)
  };
}

/**
 * Valida que los campos requeridos existan
 */
function validateRequiredFields(data, requiredFields) {
  const missing = requiredFields.filter(field => !data[field]);
  if (missing.length > 0) {
    throw new Error(`Missing required fields: ${missing.join(', ')}`);
  }
}

// ============================================================================
// CREATE PRODUCT (Write → DynamoDB)
// ============================================================================

async function createProduct(event) {
  console.log('createProduct called');
  
  try {
    const body = JSON.parse(event.body);
    
    // Validación
    validateRequiredFields(body, ['name', 'category', 'price']);
    
    // Crear item
    const timestamp = Date.now();
    const product = {
      ProductID: uuidv4(),                    // Partition Key
      Version: timestamp,                      // Sort Key (versionado)
      Name: body.name,
      Category: body.category,
      Price: Number(body.price),
      Description: body.description || '',
      Stock: Number(body.stock || 0),
      CreatedAt: timestamp,
      UpdatedAt: timestamp,
      // TTL (opcional): Expirar productos en 30 días
      ExpiresAt: body.ttl ? Math.floor(Date.now() / 1000) + (30 * 24 * 60 * 60) : undefined
    };
    
    // WRITE: Siempre va directo a DynamoDB
    const writeClient = getWriteClient();
    await writeClient.put({
      TableName: TABLE_NAME,
      Item: product,
      // Condition: No sobrescribir si ya existe esta versión
      ConditionExpression: 'attribute_not_exists(ProductID) AND attribute_not_exists(Version)'
    }).promise();
    
    console.log(`Product created: ${product.ProductID}`);
    
    return createResponse(201, {
      message: 'Product created successfully',
      product,
      metadata: {
        usedDAX: false,
        operation: 'write'
      }
    });
    
  } catch (error) {
    console.error('Error creating product:', error);
    
    if (error.code === 'ConditionalCheckFailedException') {
      return createResponse(409, {
        error: 'Product version already exists'
      });
    }
    
    return createResponse(500, {
      error: 'Failed to create product',
      message: error.message
    });
  }
}

// ============================================================================
// GET PRODUCT (Read → DAX → DynamoDB)
// ============================================================================

async function getProduct(event) {
  console.log('getProduct called');
  
  try {
    const productId = event.pathParameters?.id;
    
    if (!productId) {
      return createResponse(400, {
        error: 'ProductID is required'
      });
    }
    
    // READ: Va a DAX (si está configurado), sino a DynamoDB
    const readClient = getReadClient();
    const startTime = Date.now();
    
    // Query: Obtener la versión más reciente del producto
    const result = await readClient.query({
      TableName: TABLE_NAME,
      KeyConditionExpression: 'ProductID = :pid',
      ExpressionAttributeValues: {
        ':pid': productId
      },
      ScanIndexForward: false,  // Orden descendente (más reciente primero)
      Limit: 1                   // Solo la última versión
    }).promise();
    
    const latency = Date.now() - startTime;
    console.log(`Query completed in ${latency}ms (using DAX: ${isUsingDAX()})`);
    
    if (!result.Items || result.Items.length === 0) {
      return createResponse(404, {
        error: 'Product not found'
      });
    }
    
    return createResponse(200, {
      product: result.Items[0],
      metadata: {
        usedDAX: isUsingDAX(),
        operation: 'read',
        latencyMs: latency,
        // Estos datos ayudan a validar que DAX está funcionando
        cacheNote: isUsingDAX() 
          ? 'This read went through DAX. Subsequent reads of the same item should be faster (cache hit).'
          : 'DAX is not configured. Reading directly from DynamoDB.'
      }
    });
    
  } catch (error) {
    console.error('Error getting product:', error);
    return createResponse(500, {
      error: 'Failed to get product',
      message: error.message
    });
  }
}

// ============================================================================
// UPDATE PRODUCT (Write → DynamoDB)
// ============================================================================

async function updateProduct(event) {
  console.log('updateProduct called');
  
  try {
    const productId = event.pathParameters?.id;
    const body = JSON.parse(event.body);
    
    if (!productId) {
      return createResponse(400, {
        error: 'ProductID is required'
      });
    }
    
    // Crear nueva versión del producto
    const timestamp = Date.now();
    const updateFields = {};
    const expressionAttributeNames = {};
    const expressionAttributeValues = {};
    
    // Campos actualizables
    const updatableFields = ['Name', 'Category', 'Price', 'Description', 'Stock'];
    let updateExpression = 'SET UpdatedAt = :updatedAt, #version = :version';
    
    expressionAttributeValues[':updatedAt'] = timestamp;
    expressionAttributeValues[':version'] = timestamp;
    expressionAttributeNames['#version'] = 'Version';
    
    updatableFields.forEach(field => {
      const value = body[field.toLowerCase()];
      if (value !== undefined) {
        const attrName = `#${field.toLowerCase()}`;
        const attrValue = `:${field.toLowerCase()}`;
        
        updateExpression += `, ${attrName} = ${attrValue}`;
        expressionAttributeNames[attrName] = field;
        expressionAttributeValues[attrValue] = field === 'Price' || field === 'Stock' 
          ? Number(value) 
          : value;
      }
    });
    
    // WRITE: Directo a DynamoDB
    const writeClient = getWriteClient();
    const result = await writeClient.update({
      TableName: TABLE_NAME,
      Key: {
        ProductID: productId,
        Version: body.version || timestamp
      },
      UpdateExpression: updateExpression,
      ExpressionAttributeNames: expressionAttributeNames,
      ExpressionAttributeValues: expressionAttributeValues,
      ReturnValues: 'ALL_NEW'
    }).promise();
    
    console.log(`Product updated: ${productId}`);
    
    return createResponse(200, {
      message: 'Product updated successfully',
      product: result.Attributes,
      metadata: {
        usedDAX: false,
        operation: 'write',
        note: 'DAX cache will be invalidated automatically'
      }
    });
    
  } catch (error) {
    console.error('Error updating product:', error);
    return createResponse(500, {
      error: 'Failed to update product',
      message: error.message
    });
  }
}

// ============================================================================
// DELETE PRODUCT (Write → DynamoDB)
// ============================================================================

async function deleteProduct(event) {
  console.log('deleteProduct called');
  
  try {
    const productId = event.pathParameters?.id;
    const version = event.queryStringParameters?.version;
    
    if (!productId) {
      return createResponse(400, {
        error: 'ProductID is required'
      });
    }
    
    // WRITE: Directo a DynamoDB
    const writeClient = getWriteClient();
    
    if (version) {
      // Eliminar versión específica
      await writeClient.delete({
        TableName: TABLE_NAME,
        Key: {
          ProductID: productId,
          Version: Number(version)
        }
      }).promise();
    } else {
      // Eliminar todas las versiones (query + batch delete)
      const readClient = getReadClient();
      const result = await readClient.query({
        TableName: TABLE_NAME,
        KeyConditionExpression: 'ProductID = :pid',
        ExpressionAttributeValues: {
          ':pid': productId
        },
        ProjectionExpression: 'ProductID, #version',
        ExpressionAttributeNames: {
          '#version': 'Version'
        }
      }).promise();
      
      if (result.Items && result.Items.length > 0) {
        // Batch delete
        const deleteRequests = result.Items.map(item => ({
          DeleteRequest: {
            Key: {
              ProductID: item.ProductID,
              Version: item.Version
            }
          }
        }));
        
        await writeClient.batchWrite({
          RequestItems: {
            [TABLE_NAME]: deleteRequests
          }
        }).promise();
      }
    }
    
    console.log(`Product deleted: ${productId}`);
    
    return createResponse(200, {
      message: 'Product deleted successfully',
      metadata: {
        usedDAX: false,
        operation: 'write'
      }
    });
    
  } catch (error) {
    console.error('Error deleting product:', error);
    return createResponse(500, {
      error: 'Failed to delete product',
      message: error.message
    });
  }
}

// ============================================================================
// LIST PRODUCTS (Read → DAX → DynamoDB)
// ============================================================================

async function listProducts(event) {
  console.log('listProducts called');
  
  try {
    const category = event.queryStringParameters?.category;
    const limit = parseInt(event.queryStringParameters?.limit || '20');
    
    const readClient = getReadClient();
    const startTime = Date.now();
    
    let result;
    
    if (category) {
      // Query por GSI (CategoryIndex)
      result = await readClient.query({
        TableName: TABLE_NAME,
        IndexName: 'CategoryIndex',
        KeyConditionExpression: 'Category = :category',
        ExpressionAttributeValues: {
          ':category': category
        },
        Limit: limit
      }).promise();
    } else {
      // Scan (no recomendado en producción con tablas grandes)
      result = await readClient.scan({
        TableName: TABLE_NAME,
        Limit: limit
      }).promise();
    }
    
    const latency = Date.now() - startTime;
    console.log(`List query completed in ${latency}ms (using DAX: ${isUsingDAX()})`);
    
    return createResponse(200, {
      products: result.Items || [],
      count: result.Count,
      metadata: {
        usedDAX: isUsingDAX(),
        operation: 'read',
        latencyMs: latency,
        hasMoreResults: !!result.LastEvaluatedKey
      }
    });
    
  } catch (error) {
    console.error('Error listing products:', error);
    return createResponse(500, {
      error: 'Failed to list products',
      message: error.message
    });
  }
}

// ============================================================================
// HANDLER PRINCIPAL
// ============================================================================

exports.handler = async (event) => {
  console.log('Event:', JSON.stringify(event, null, 2));
  
  // Validar que TABLE_NAME esté configurado
  if (!TABLE_NAME) {
    return createResponse(500, {
      error: 'TABLE_NAME environment variable not configured'
    });
  }
  
  // Route por HTTP method y path
  const method = event.httpMethod;
  const path = event.path;
  
  try {
    if (method === 'POST' && path === '/products') {
      return await createProduct(event);
    }
    
    if (method === 'GET' && event.pathParameters?.id) {
      return await getProduct(event);
    }
    
    if (method === 'GET' && path === '/products') {
      return await listProducts(event);
    }
    
    if (method === 'PUT' && event.pathParameters?.id) {
      return await updateProduct(event);
    }
    
    if (method === 'DELETE' && event.pathParameters?.id) {
      return await deleteProduct(event);
    }
    
    return createResponse(404, {
      error: 'Route not found'
    });
    
  } catch (error) {
    console.error('Unhandled error:', error);
    return createResponse(500, {
      error: 'Internal server error',
      message: error.message
    });
  }
};

// ============================================================================
// ¿QUÉ DIRÍA UN SENIOR EN UNA ENTREVISTA?
// ============================================================================
// "Esta Lambda implementa un patrón CQRS simplificado: separación entre
// commands (writes) y queries (reads).
//
// Los writes siempre van directo a DynamoDB por consistencia. Los reads
// usan DAX cuando está disponible, lo que reduce latencia y costo de RCUs.
//
// El schema usa versionado (ProductID + Version) para mantener historial.
// En producción, probablemente tendríamos dos tablas: una para la versión
// actual y otra para el historial.
//
// El GSI (CategoryIndex) permite queries eficientes por categoría. Sin él,
// tendríamos que hacer un Scan, que es ineficiente y caro en tablas grandes.
//
// Incluimos metadata en las respuestas (usedDAX, latency) para facilitar
// debugging y validación. En producción, esto iría a CloudWatch Logs y
// métricas custom.
//
// MEJORAS PARA PRODUCCIÓN:
// 1. Validación de input más robusta (schema validation)
// 2. Paginación correcta (LastEvaluatedKey)
// 3. Rate limiting
// 4. Distributed tracing (X-Ray)
// 5. Structured logging
// 6. Error handling más granular
// 7. Unit tests y integration tests"
// ============================================================================
