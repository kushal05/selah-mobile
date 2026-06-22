/// Server Sync Endpoints Specification
///
/// Per spec section 7:
/// Server Sync Endpoints:
/// - Push operations endpoint
/// - Pull operations endpoint
/// - WebSocket / real-time trigger logic
/// - Validation rules
///
/// This file defines the API contract for backend implementation.
library;

// ============================================================
// PUSH ENDPOINT
// ============================================================

/// POST /v1/sync/push
///
/// Push a single operation from client to server.
///
/// Per spec section 5.2:
/// - Push order must be preserved
/// - Server uses op_id for idempotency
///
/// Request:
/// ```json
/// {
///   "opId": "uuid",
///   "entityType": "folder | note | note_block",
///   "entityId": "uuid",
///   "operation": "INSERT | UPDATE | DELETE",
///   "payload": { ... full entity state ... },
///   "timestamp": 1700000000,
///   "deviceId": "uuid",
///   "entityVersion": 5
/// }
/// ```
///
/// Response (200 OK):
/// ```json
/// {
///   "success": true,
///   "serverTimestamp": 1700000001,
///   "opId": "uuid"
/// }
/// ```
///
/// Response (409 Conflict - version conflict):
/// ```json
/// {
///   "success": false,
///   "error": "VERSION_CONFLICT",
///   "currentVersion": 6,
///   "message": "Entity has been modified"
/// }
/// ```
///
/// Implementation pseudocode:
/// ```
/// async function pushOperation(req, res) {
///   const { opId, entityType, entityId, operation, payload, timestamp, deviceId, entityVersion } = req.body;
///   const userId = req.user.id;
///
///   // 1. Idempotency check
///   const existingOp = await operations.findById(opId);
///   if (existingOp) {
///     return res.json({ success: true, serverTimestamp: existingOp.serverTimestamp, opId });
///   }
///
///   // 2. Get collection based on entityType
///   const collection = getCollection(entityType);
///
///   // 3. Apply operation
///   const serverTimestamp = Date.now();
///
///   await db.transaction(async (session) => {
///     switch (operation) {
///       case 'INSERT':
///         await collection.insertOne({
///           _id: entityId,
///           ...payload,
///           updatedAt: serverTimestamp
///         }, { session });
///         break;
///
///       case 'UPDATE':
///         const result = await collection.updateOne(
///           { _id: entityId },
///           { $set: { ...payload, updatedAt: serverTimestamp } },
///           { session }
///         );
///         break;
///
///       case 'DELETE':
///         await collection.updateOne(
///           { _id: entityId },
///           { $set: { deleted: true, updatedAt: serverTimestamp, version: entityVersion } },
///           { session }
///         );
///         break;
///     }
///
///     // 4. Record operation for audit/sync
///     await operations.insertOne({
///       _id: opId,
///       entityType,
///       entityId,
///       operation,
///       payload,
///       timestamp,
///       serverTimestamp,
///       deviceId,
///       userId,
///       entityVersion
///     }, { session });
///   });
///
///   return res.json({ success: true, serverTimestamp, opId });
/// }
/// ```
class PushEndpointSpec {
  static const method = 'POST';
  static const path = '/v1/sync/push';

  static const requestSchema = {
    'opId': 'string (required) - UUID, used for idempotency',
    'entityType': 'string (required) - folder | note | note_block',
    'entityId': 'string (required) - UUID of entity',
    'operation': 'string (required) - INSERT | UPDATE | DELETE',
    'payload': 'object (required) - Full entity state',
    'timestamp': 'int64 (required) - Client timestamp',
    'deviceId': 'string (required) - Client device ID',
    'entityVersion': 'int32 (required) - Version at time of op',
  };

  static const responseSchema = {
    'success': 'boolean',
    'serverTimestamp': 'int64 - Server timestamp when applied',
    'opId': 'string - Echo back op_id',
    'error': 'string (on failure) - Error code',
    'message': 'string (on failure) - Human readable message',
  };

  static const validationRules = '''
    1. Authenticate user (JWT/session)
    2. Validate opId is UUID format
    3. Validate entityType is valid enum
    4. Validate operation is valid enum
    5. Validate payload matches entityType schema
    6. Check user owns the entity
    7. Check entityVersion for conflicts (optional - LWW means we may skip)
  ''';
}

// ============================================================
// PUSH BATCH ENDPOINT
// ============================================================

/// POST /v1/sync/push-batch
///
/// Push multiple operations in order.
///
/// Request:
/// ```json
/// {
///   "operations": [
///     { ...operation1... },
///     { ...operation2... }
///   ]
/// }
/// ```
///
/// Response:
/// ```json
/// {
///   "success": true,
///   "results": [
///     { "opId": "...", "serverTimestamp": 1234 },
///     { "opId": "...", "serverTimestamp": 1235 }
///   ]
/// }
/// ```
class PushBatchEndpointSpec {
  static const method = 'POST';
  static const path = '/v1/sync/push-batch';

  static const notes = '''
    - Operations MUST be applied in order
    - If any operation fails, subsequent ops should still be attempted
    - Return results for each operation
    - Maximum batch size: 100 operations
  ''';
}

// ============================================================
// PULL ENDPOINT
// ============================================================

/// GET /v1/sync/pull
///
/// Pull operations from server since last cursor.
///
/// Per spec section 5.3:
/// Server returns cursor and operations.
/// Client applies ops in order and updates cursor.
///
/// Request:
/// ```
/// GET /v1/sync/pull?cursor=abc123&limit=100
/// ```
///
/// Response:
/// ```json
/// {
///   "cursor": "def456",
///   "operations": [
///     {
///       "opId": "...",
///       "entityType": "note",
///       "entityId": "...",
///       "operation": "UPDATE",
///       "payload": { ... },
///       "timestamp": 1700000000,
///       "serverTimestamp": 1700000001,
///       "deviceId": "...",
///       "entityVersion": 5
///     }
///   ],
///   "batchSize": 100,
///   "hasMore": true
/// }
/// ```
///
/// Implementation pseudocode:
/// ```
/// async function pullOperations(req, res) {
///   const userId = req.user.id;
///   const deviceId = req.query.deviceId;
///   const cursor = req.query.cursor;
///   const limit = Math.min(parseInt(req.query.limit) || 100, 100);
///
///   // Parse cursor (timestamp-based)
///   const lastTimestamp = cursor ? parseInt(cursor) : 0;
///
///   // Query operations newer than cursor
///   // EXCLUDE operations from same device (they already have them)
///   const ops = await operations.find({
///     userId: userId,
///     serverTimestamp: { $gt: lastTimestamp },
///     deviceId: { $ne: deviceId }
///   })
///   .sort({ serverTimestamp: 1 })
///   .limit(limit + 1)
///   .toArray();
///
///   const hasMore = ops.length > limit;
///   if (hasMore) ops.pop();
///
///   // New cursor is the last operation's timestamp
///   const newCursor = ops.length > 0
///     ? ops[ops.length - 1].serverTimestamp.toString()
///     : cursor;
///
///   // Update sync cursor for this device
///   await syncCursors.updateOne(
///     { _id: `${userId}_${deviceId}` },
///     {
///       $set: {
///         cursor: newCursor,
///         lastSyncAt: Date.now()
///       },
///       $setOnInsert: {
///         userId,
///         deviceId,
///         createdAt: Date.now()
///       }
///     },
///     { upsert: true }
///   );
///
///   return res.json({
///     cursor: newCursor,
///     operations: ops,
///     batchSize: limit,
///     hasMore
///   });
/// }
/// ```
class PullEndpointSpec {
  static const method = 'GET';
  static const path = '/v1/sync/pull';

  static const queryParams = {
    'cursor': 'string (optional) - Last sync cursor',
    'deviceId': 'string (required) - Current device ID',
    'limit': 'int (optional, default=100, max=100) - Batch size',
  };

  static const responseSchema = {
    'cursor': 'string - New cursor for next pull',
    'operations': 'array - List of operations to apply',
    'batchSize': 'int - Requested batch size',
    'hasMore': 'boolean - More operations available',
  };

  static const notes = '''
    1. Operations are ordered by serverTimestamp ASC
    2. Exclude operations from the requesting device
    3. Cursor is opaque to client (implementation can change)
    4. hasMore indicates if another pull is needed
    5. Empty operations array means client is up to date
  ''';
}

// ============================================================
// WEBSOCKET ENDPOINT
// ============================================================

/// WS /v1/sync/ws
///
/// WebSocket connection for real-time sync notifications.
///
/// Per spec section 8:
/// MongoDB change -> Backend emits event -> WebSocket push to clients
/// Client NEVER trusts payload directly – always re-applies via sync engine
///
/// Connection:
/// ```
/// ws://server/v1/sync/ws?token=jwt_token&deviceId=uuid
/// ```
///
/// Server -> Client messages (application-level JSON):
/// ```json
/// { "type": "sync_available" }
/// { "type": "session_revoked" }
/// { "type": "error", "message": "..." }
/// ```
///
/// Keepalive: Server sends WebSocket protocol-level pings (opcode 0x9)
/// every 30s. The client's WebSocket library auto-responds with
/// protocol-level pongs. No application-level ping/pong JSON messages
/// are used.
///
/// Implementation notes:
/// ```
/// // On MongoDB Change Stream event
/// changeStream.on('change', async (change) => {
///   const userId = change.fullDocument?.userId;
///   if (!userId) return;
///
///   // Find all WebSocket connections for this user
///   const connections = wsConnections.get(userId) || [];
///
///   // Notify each connection (except the one that made the change)
///   const sourceDeviceId = change.fullDocument?.lastModifiedBy;
///   for (const conn of connections) {
///     if (conn.deviceId !== sourceDeviceId) {
///       conn.send(JSON.stringify({ type: 'sync_available' }));
///     }
///   }
/// });
/// ```
class WebSocketEndpointSpec {
  static const path = '/v1/sync/ws';

  static const connectionParams = {
    'token': 'string (required) - JWT auth token',
    'deviceId': 'string (required) - Device ID',
  };

  static const serverMessages = {
    'sync_available': 'New data available, client should pull',
    'ping': 'Keepalive ping, client should respond with pong',
    'error': 'Error message, may include disconnect',
  };

  static const clientMessages = {
    'pong': 'Response to ping',
    'subscribe': 'Subscribe to user updates (if not in token)',
  };

  static const notes = '''
    Per spec section 8:
    - Client NEVER trusts payload directly
    - sync_available just triggers a pull
    - This ensures all data goes through conflict resolution
    - Keepalive ping every 30 seconds
    - Reconnect with exponential backoff on disconnect
  ''';
}

// ============================================================
// VALIDATION RULES
// ============================================================

/// Validation rules for all sync operations
///
/// Per spec:
/// - Every entity must have id, updatedAt, version, deleted
/// - No hard deletes
/// - All writes must be authenticated
class ValidationRules {
  static const entityRules = '''
    All entities must have:
    - id: UUID, immutable after creation
    - updatedAt: Unix milliseconds, updated on every change
    - version: Integer >= 1, incremented on every change
    - deleted: Boolean, only transitions false -> true
    - createdAt: Unix milliseconds, immutable after creation
    - userId: UUID, must match authenticated user
  ''';

  static const operationRules = '''
    INSERT:
    - Entity must not exist
    - All required fields must be present
    - version must be 1
    - deleted must be false

    UPDATE:
    - Entity must exist
    - userId must match entity owner
    - version must be > current version (or use LWW)
    - Cannot update id, createdAt

    DELETE:
    - Entity must exist
    - userId must match entity owner
    - Sets deleted = true (soft delete)
    - Never removes the document
  ''';

  static const securityRules = '''
    - All endpoints require authentication
    - Users can only access their own data
    - Rate limiting on push operations
    - Maximum payload size: 1MB
    - Maximum operations per batch: 100
  ''';
}

// ============================================================
// ERROR CODES
// ============================================================

/// Standard error codes for sync API
class SyncErrorCodes {
  static const codes = {
    'AUTH_REQUIRED': 'Authentication required',
    'AUTH_INVALID': 'Invalid or expired token',
    'FORBIDDEN': 'User does not own this entity',
    'NOT_FOUND': 'Entity not found',
    'VERSION_CONFLICT': 'Entity version conflict',
    'VALIDATION_ERROR': 'Invalid request data',
    'RATE_LIMITED': 'Too many requests',
    'PAYLOAD_TOO_LARGE': 'Request payload too large',
    'INTERNAL_ERROR': 'Server error',
    'TOKEN_REUSE_DETECTED': 'Refresh token reuse detected',
    'REQUEST_TIMEOUT': 'Request timeout',
    'INVALID_JSON': 'Invalid JSON request body',
    'INVALID_REQUEST': 'Invalid request',
  };
}
