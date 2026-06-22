# Backend Implementation Guide

Complete technical specification for building the PersonalNotify backend server.

---

## Table of Contents

1. [Overview](#1-overview)
2. [Technology Stack](#2-technology-stack)
3. [Architecture](#3-architecture)
4. [Database Schema](#4-database-schema)
5. [API Endpoints](#5-api-endpoints)
6. [Authentication](#6-authentication)
7. [Sync Protocol](#7-sync-protocol)
8. [Conflict Resolution](#8-conflict-resolution)
9. [Real-time Updates](#9-real-time-updates)
10. [Error Handling](#10-error-handling)
11. [Security](#11-security)
12. [Deployment](#12-deployment)

---

## 1. Overview

PersonalNotify is an offline-first spiritual notes application that requires a backend to synchronize data across multiple devices. The backend serves as an **eventual consistency replica** - the client's local database is always the source of truth.

### Core Principles

1. **Local database is the single source of truth** (client-side)
2. **UI never waits for the network**
3. **Every mutation is durable locally before syncing**
4. **Sync is eventual, deterministic, and replayable**
5. **All operations must be idempotent**

### Supported Entity Types

| Entity | Description |
|--------|-------------|
| `folder` | Hierarchical folder organization |
| `note` | Note metadata (title, folder, dates) |
| `note_block` | Rich content blocks within notes |
| `prayer` | Prayer requests with status tracking |
| `promise` | Bible verses/promises |
| `person` | People to pray for |
| `song` | Song lyrics and chords |

---

## 2. Technology Stack

### Recommended Stack

| Component | Technology | Notes |
|-----------|------------|-------|
| Runtime | Node.js 20+ / Go / Python | Any language works |
| Framework | Express.js / Fastify / Gin / FastAPI | REST + WebSocket support |
| Database | MongoDB Atlas | Change streams for real-time |
| Auth | JWT (RS256) | With refresh tokens |
| WebSocket | Socket.io / ws | For real-time notifications |
| Cache | Redis (optional) | Rate limiting, sessions |

### Why MongoDB?

- Document structure mirrors client-side entities
- Change Streams enable real-time notifications
- Flexible schema for JSON content fields
- Built-in TTL indexes for audit log cleanup

---

## 3. Architecture

### High-Level Flow

```
Client (Flutter)
    |
    v
[HTTP/WebSocket]
    |
    v
+-------------------+
|   API Gateway     |
|   (Auth + Rate)   |
+-------------------+
    |
    v
+-------------------+
|   Sync Service    |
|   - Push Handler  |
|   - Pull Handler  |
|   - WebSocket     |
+-------------------+
    |
    v
+-------------------+
|   MongoDB Atlas   |
|   - Collections   |
|   - Change Stream |
+-------------------+
```

### Request Flow

1. Client sends push request with JWT token
2. Server validates token, extracts userId
3. Server applies operation with idempotency check
4. Server records operation in audit log
5. Change stream triggers WebSocket notification to other devices
6. Other devices pull new operations

---

## 4. Database Schema

### 4.1 Collections Overview

| Collection | Purpose |
|------------|---------|
| `users` | User accounts and profiles |
| `folders` | Folder hierarchy |
| `notes` | Note metadata |
| `note_blocks` | Note content blocks |
| `prayers` | Prayer requests |
| `promises` | Bible promises |
| `people` | People to pray for |
| `songs` | Song lyrics/chords |
| `operations` | Sync audit log (TTL: 90 days) |
| `sync_cursors` | Per-device sync position |
| `devices` | Device registry |

### 4.2 Common Fields (All Entity Collections)

Every entity document MUST have these fields:

```javascript
{
  "_id": "uuid-string",      // Primary key, immutable
  "userId": "uuid-string",   // Owner (for access control)
  "createdAt": 1700000000,   // Unix ms, immutable
  "updatedAt": 1700000000,   // Unix ms, updated on every change
  "version": 1,              // Integer >= 1, incremented on change
  "deleted": false           // Soft delete flag (never hard delete)
}
```

### 4.3 Folders Collection

```javascript
// Collection: folders
{
  "_id": "folder_uuid",
  "parentId": "parent_folder_uuid" | null,  // null = root folder
  "name": "Sermons",
  "userId": "user_uuid",
  "createdAt": 1700000000,
  "updatedAt": 1700000000,
  "version": 1,
  "deleted": false
}

// Indexes
db.folders.createIndex({ "userId": 1, "deleted": 1, "name": 1 })
db.folders.createIndex({ "parentId": 1, "deleted": 1 })
db.folders.createIndex({ "userId": 1, "updatedAt": 1 })
```

### 4.4 Notes Collection

```javascript
// Collection: notes
{
  "_id": "note_uuid",
  "folderId": "folder_uuid",
  "userId": "user_uuid",
  "title": "Sunday Sermon Notes",
  "preacherId": "preacher_uuid" | null,  // Optional reference
  "noteDate": 1700000000 | null,         // Optional timestamp
  "createdAt": 1700000000,
  "updatedAt": 1700000000,
  "version": 1,
  "deleted": false
}

// Indexes
db.notes.createIndex({ "folderId": 1, "deleted": 1, "updatedAt": -1 })
db.notes.createIndex({ "userId": 1, "deleted": 1, "updatedAt": -1 })
db.notes.createIndex({ "userId": 1, "updatedAt": 1 })
db.notes.createIndex({ "preacherId": 1, "deleted": 1 })
db.notes.createIndex({ "title": "text" })  // Full-text search
```

### 4.5 Note Blocks Collection

```javascript
// Collection: note_blocks
{
  "_id": "block_uuid",
  "noteId": "note_uuid",
  "blockType": "paragraph",  // See block types below
  "content": {               // JSON structure varies by type
    "text": "Lorem ipsum...",
    "spans": [
      { "text": "bold text", "bold": true },
      { "text": "italic", "italic": true }
    ]
  },
  "orderIndex": 0,           // Position in note (0-indexed)
  "createdAt": 1700000000,
  "updatedAt": 1700000000,
  "version": 1,
  "deleted": false
}

// Block Types
const BLOCK_TYPES = [
  'paragraph',
  'heading1',
  'heading2',
  'heading3',
  'bulletList',
  'numberedList',
  'checkbox',
  'quote',
  'code',
  'divider',
  'image'
];

// Block Content Schemas
// paragraph/heading/quote: { text: string, spans?: Span[] }
// bulletList/numberedList: { text: string, indent: number }
// checkbox: { text: string, checked: boolean }
// code: { text: string, language?: string }
// divider: {} (empty)
// image: { url: string, caption?: string, width?: number, height?: number }

// Indexes
db.note_blocks.createIndex({ "noteId": 1, "deleted": 1, "orderIndex": 1 })
db.note_blocks.createIndex({ "noteId": 1, "updatedAt": 1 })
db.note_blocks.createIndex({ "content.text": "text" })  // Full-text search
```

### 4.6 Prayers Collection

```javascript
// Collection: prayers
{
  "_id": "prayer_uuid",
  "userId": "user_uuid",
  "title": "Healing for John",
  "content": "Please pray for John's recovery from surgery...",
  "frequency": "daily",      // daily | weekdays | weekly | monthly | asNeeded
  "status": "active",        // active | answered | archived
  "category": "Health",      // Optional tag
  "answeredAt": null,        // Timestamp when answered (null if not)
  "createdAt": 1700000000,
  "updatedAt": 1700000000,
  "version": 1,
  "deleted": false
}

// Indexes
db.prayers.createIndex({ "userId": 1, "deleted": 1, "status": 1 })
db.prayers.createIndex({ "userId": 1, "updatedAt": 1 })
db.prayers.createIndex({ "userId": 1, "frequency": 1, "status": 1 })
```

### 4.7 Promises Collection

```javascript
// Collection: promises
{
  "_id": "promise_uuid",
  "userId": "user_uuid",
  "reference": "Jeremiah 29:11",
  "content": "For I know the plans I have for you...",
  "preview": "For I know the plans I have for you...",  // First 50 chars
  "notes": "This verse gives me hope during difficult times",
  "category": "Hope",        // Optional tag
  "isFavorite": false,
  "createdAt": 1700000000,
  "updatedAt": 1700000000,
  "version": 1,
  "deleted": false
}

// Indexes
db.promises.createIndex({ "userId": 1, "deleted": 1, "isFavorite": -1 })
db.promises.createIndex({ "userId": 1, "updatedAt": 1 })
db.promises.createIndex({ "reference": "text", "content": "text" })
```

### 4.8 People Collection

```javascript
// Collection: people
{
  "_id": "person_uuid",
  "userId": "user_uuid",
  "name": "John Smith",
  "relation": "Church Member",  // Family | Friend | Church Member | etc.
  "email": "john@example.com",  // Optional
  "phone": "+1234567890",       // Optional
  "notes": "Pray for his job search",
  "imageUrl": "https://...",    // Optional profile image
  "createdAt": 1700000000,
  "updatedAt": 1700000000,
  "version": 1,
  "deleted": false
}

// Indexes
db.people.createIndex({ "userId": 1, "deleted": 1, "name": 1 })
db.people.createIndex({ "userId": 1, "updatedAt": 1 })
db.people.createIndex({ "userId": 1, "relation": 1 })
```

### 4.9 Songs Collection

```javascript
// Collection: songs
{
  "_id": "song_uuid",
  "userId": "user_uuid",
  "title": "Amazing Grace",
  "folderId": "folder_uuid" | null,  // Optional folder
  "lyrics": "Amazing grace, how sweet the sound...",
  "chords": "[G]Amazing [C]grace, how [G]sweet...",  // With inline chords
  "language": "English",
  "book": "Hymnal",          // Optional songbook reference
  "preview": "Amazing grace, how sweet the sound...",  // First 50 chars
  "tags": "hymn,classic,worship",  // Comma-separated
  "hasChords": true,
  "isFavorite": false,
  "createdAt": 1700000000,
  "updatedAt": 1700000000,
  "version": 1,
  "deleted": false
}

// Indexes
db.songs.createIndex({ "userId": 1, "deleted": 1, "title": 1 })
db.songs.createIndex({ "userId": 1, "language": 1 })
db.songs.createIndex({ "userId": 1, "updatedAt": 1 })
db.songs.createIndex({ "folderId": 1, "deleted": 1 })
db.songs.createIndex({ "title": "text", "lyrics": "text" })
```

### 4.10 Operations Collection (Audit Log)

```javascript
// Collection: operations
{
  "_id": "op_uuid",          // Operation ID (for idempotency)
  "entityType": "note",      // folder | note | note_block | prayer | promise | person | song
  "entityId": "entity_uuid",
  "operation": "UPDATE",     // INSERT | UPDATE | DELETE
  "payload": { ... },        // Full entity state at time of operation
  "timestamp": 1700000000,   // Client timestamp
  "serverTimestamp": 1700000001,  // Server timestamp when received
  "deviceId": "device_uuid",
  "userId": "user_uuid",
  "entityVersion": 5
}

// Indexes
db.operations.createIndex({ "_id": 1 })  // Idempotency lookup
db.operations.createIndex({ "entityType": 1, "entityId": 1, "timestamp": 1 })
db.operations.createIndex({ "userId": 1, "serverTimestamp": 1 })

// TTL Index - auto-delete after 90 days
db.operations.createIndex(
  { "serverTimestamp": 1 },
  { expireAfterSeconds: 7776000 }
)
```

### 4.11 Sync Cursors Collection

```javascript
// Collection: sync_cursors
{
  "_id": "userId_deviceId",  // Compound key
  "userId": "user_uuid",
  "deviceId": "device_uuid",
  "cursor": "1700000001",    // Last serverTimestamp received
  "lastSyncAt": 1700000000,
  "createdAt": 1700000000
}

// Indexes
db.sync_cursors.createIndex({ "userId": 1 })
db.sync_cursors.createIndex({ "deviceId": 1 })
```

### 4.12 Devices Collection

```javascript
// Collection: devices
{
  "_id": "device_uuid",
  "userId": "user_uuid",
  "name": "John's iPhone",
  "platform": "ios",         // ios | android | web | macos | windows | linux
  "appVersion": "1.2.0",
  "createdAt": 1700000000,
  "lastActiveAt": 1700000000
}

// Indexes
db.devices.createIndex({ "userId": 1, "lastActiveAt": -1 })
```

### 4.13 Users Collection

```javascript
// Collection: users
{
  "_id": "user_uuid",
  "email": "user@example.com",
  "passwordHash": "$argon2id$...",  // Argon2id hash
  "name": "John Doe",
  "emailVerified": true,
  "createdAt": 1700000000,
  "updatedAt": 1700000000
}

// Indexes
db.users.createIndex({ "email": 1 }, { unique: true })
```

---

## 5. API Endpoints

### Base URL

```
Production: https://selah-api.kotikushal05.workers.dev/v1
Development: https://selah-api.kotikushal05.workers.dev/v1
```

### 5.1 Authentication Endpoints

#### Register User

```http
POST /auth/register
Content-Type: application/json

{
  "email": "user@example.com",
  "password": "securePassword123",
  "name": "John Doe"
}

Response (201 Created):
{
  "success": true,
  "user": {
    "id": "user_uuid",
    "email": "user@example.com",
    "name": "John Doe"
  },
  "tokens": {
    "accessToken": "eyJhbG...",
    "refreshToken": "eyJhbG...",
    "expiresAt": 1700003600
  }
}

Response (400 Bad Request):
{
  "success": false,
  "error": "VALIDATION_ERROR",
  "message": "Email already registered"
}
```

#### Login

```http
POST /auth/login
Content-Type: application/json

{
  "email": "user@example.com",
  "password": "securePassword123",
  "deviceId": "device_uuid",
  "deviceName": "John's iPhone",
  "platform": "ios"
}

Response (200 OK):
{
  "success": true,
  "user": {
    "id": "user_uuid",
    "email": "user@example.com",
    "name": "John Doe"
  },
  "tokens": {
    "accessToken": "eyJhbG...",
    "refreshToken": "eyJhbG...",
    "expiresAt": 1700003600
  }
}

Response (401 Unauthorized):
{
  "success": false,
  "error": "AUTH_INVALID",
  "message": "Invalid email or password"
}
```

#### Refresh Token

```http
POST /auth/refresh
Content-Type: application/json

{
  "refreshToken": "eyJhbG..."
}

Response (200 OK):
{
  "success": true,
  "tokens": {
    "accessToken": "eyJhbG...",
    "refreshToken": "eyJhbG...",
    "expiresAt": 1700003600
  }
}
```

#### Logout

```http
POST /auth/logout
Authorization: Bearer <access_token>

Response (200 OK):
{
  "success": true
}
```

### 5.2 Sync Endpoints

#### Push Single Operation

```http
POST /sync/push
Authorization: Bearer <access_token>
Content-Type: application/json

{
  "opId": "op_uuid",
  "entityType": "note",
  "entityId": "note_uuid",
  "operation": "UPDATE",
  "payload": {
    "id": "note_uuid",
    "folderId": "folder_uuid",
    "userId": "user_uuid",
    "title": "Updated Title",
    "updatedAt": 1700000000,
    "version": 5,
    "deleted": false,
    "createdAt": 1699000000
  },
  "timestamp": 1700000000,
  "deviceId": "device_uuid",
  "entityVersion": 5
}

Response (200 OK):
{
  "success": true,
  "serverTimestamp": 1700000001,
  "opId": "op_uuid"
}

Response (409 Conflict):
{
  "success": false,
  "error": "VERSION_CONFLICT",
  "currentVersion": 6,
  "message": "Entity has been modified"
}
```

#### Push Batch Operations

```http
POST /sync/push-batch
Authorization: Bearer <access_token>
Content-Type: application/json

{
  "operations": [
    {
      "opId": "op_uuid_1",
      "entityType": "folder",
      "entityId": "folder_uuid",
      "operation": "INSERT",
      "payload": { ... },
      "timestamp": 1700000000,
      "deviceId": "device_uuid",
      "entityVersion": 1
    },
    {
      "opId": "op_uuid_2",
      "entityType": "note",
      "entityId": "note_uuid",
      "operation": "INSERT",
      "payload": { ... },
      "timestamp": 1700000001,
      "deviceId": "device_uuid",
      "entityVersion": 1
    }
  ]
}

Response (200 OK):
{
  "success": true,
  "results": [
    { "opId": "op_uuid_1", "serverTimestamp": 1700000002, "success": true },
    { "opId": "op_uuid_2", "serverTimestamp": 1700000003, "success": true }
  ]
}
```

**Batch Push Rules:**
- Operations MUST be applied in order
- If one operation fails, subsequent ops should still be attempted
- Maximum batch size: 100 operations
- Maximum payload size: 1MB

#### Pull Operations

```http
GET /sync/pull?cursor=1700000000&limit=100&deviceId=device_uuid
Authorization: Bearer <access_token>

Response (200 OK):
{
  "cursor": "1700000500",
  "operations": [
    {
      "opId": "op_uuid",
      "entityType": "note",
      "entityId": "note_uuid",
      "operation": "UPDATE",
      "payload": { ... },
      "timestamp": 1700000100,
      "serverTimestamp": 1700000101,
      "deviceId": "other_device_uuid",
      "entityVersion": 3
    }
  ],
  "batchSize": 100,
  "hasMore": true
}
```

**Pull Rules:**
- Operations are ordered by `serverTimestamp` ASC
- EXCLUDE operations from the requesting device
- `cursor` is the last `serverTimestamp` received
- `hasMore` indicates if another pull is needed
- Empty `operations` array means client is up to date

### 5.3 Pull Implementation Pseudocode

```javascript
async function pullOperations(req, res) {
  const userId = req.user.id;
  const deviceId = req.query.deviceId;
  const cursor = req.query.cursor || '0';
  const limit = Math.min(parseInt(req.query.limit) || 100, 100);

  const lastTimestamp = parseInt(cursor);

  // Query operations newer than cursor, excluding same device
  const ops = await db.operations.find({
    userId: userId,
    serverTimestamp: { $gt: lastTimestamp },
    deviceId: { $ne: deviceId }
  })
  .sort({ serverTimestamp: 1 })
  .limit(limit + 1)
  .toArray();

  const hasMore = ops.length > limit;
  if (hasMore) ops.pop();

  // New cursor is last operation's serverTimestamp
  const newCursor = ops.length > 0
    ? ops[ops.length - 1].serverTimestamp.toString()
    : cursor;

  // Update sync cursor for this device
  await db.sync_cursors.updateOne(
    { _id: `${userId}_${deviceId}` },
    {
      $set: { cursor: newCursor, lastSyncAt: Date.now() },
      $setOnInsert: { userId, deviceId, createdAt: Date.now() }
    },
    { upsert: true }
  );

  return res.json({
    cursor: newCursor,
    operations: ops,
    batchSize: limit,
    hasMore
  });
}
```

### 5.4 Push Implementation Pseudocode

```javascript
async function pushOperation(req, res) {
  const { opId, entityType, entityId, operation, payload, timestamp, deviceId, entityVersion } = req.body;
  const userId = req.user.id;

  // 1. Idempotency check
  const existingOp = await db.operations.findOne({ _id: opId });
  if (existingOp) {
    return res.json({
      success: true,
      serverTimestamp: existingOp.serverTimestamp,
      opId
    });
  }

  // 2. Validate user owns entity (for UPDATE/DELETE)
  if (operation !== 'INSERT') {
    const collection = getCollection(entityType);
    const existing = await collection.findOne({ _id: entityId });
    if (!existing) {
      return res.status(404).json({ success: false, error: 'NOT_FOUND' });
    }
    if (existing.userId !== userId) {
      return res.status(403).json({ success: false, error: 'FORBIDDEN' });
    }
  }

  // 3. Generate server timestamp
  const serverTimestamp = Date.now();

  // 4. Apply operation in transaction
  const session = client.startSession();
  try {
    await session.withTransaction(async () => {
      const collection = getCollection(entityType);

      switch (operation) {
        case 'INSERT':
          await collection.insertOne({
            ...payload,
            _id: entityId,
            userId,
            updatedAt: serverTimestamp
          }, { session });
          break;

        case 'UPDATE':
          await collection.updateOne(
            { _id: entityId },
            { $set: { ...payload, updatedAt: serverTimestamp } },
            { session }
          );
          break;

        case 'DELETE':
          // Soft delete only
          await collection.updateOne(
            { _id: entityId },
            { $set: { deleted: true, updatedAt: serverTimestamp, version: entityVersion } },
            { session }
          );
          break;
      }

      // 5. Record operation for audit/sync
      await db.operations.insertOne({
        _id: opId,
        entityType,
        entityId,
        operation,
        payload,
        timestamp,
        serverTimestamp,
        deviceId,
        userId,
        entityVersion
      }, { session });
    });

    return res.json({ success: true, serverTimestamp, opId });
  } finally {
    await session.endSession();
  }
}

function getCollection(entityType) {
  const collections = {
    'folder': db.folders,
    'note': db.notes,
    'note_block': db.note_blocks,
    'prayer': db.prayers,
    'promise': db.promises,
    'person': db.people,
    'song': db.songs
  };
  return collections[entityType];
}
```

---

## 6. Authentication

### JWT Token Structure

```javascript
// Access Token (1 hour expiry)
{
  "sub": "user_uuid",
  "email": "user@example.com",
  "iat": 1700000000,
  "exp": 1700003600,
  "type": "access"
}

// Refresh Token (30 days expiry)
{
  "sub": "user_uuid",
  "iat": 1700000000,
  "exp": 1702592000,
  "type": "refresh",
  "jti": "random_uuid"  // For revocation
}
```

### Token Handling

1. **Access Token**: Sent in `Authorization: Bearer <token>` header
2. **Refresh Token**: Stored securely, used to get new access tokens
3. **Token Refresh**: Client should refresh when token expires or is about to expire (within 5 minutes)

### Password Requirements

- Minimum 8 characters
- Use Argon2id for hashing
- Salt automatically included by Argon2

---

## 7. Sync Protocol

### Sync State Machine (Client)

```
States:
- idle          // Waiting to sync
- pushing       // Sending local ops to server
- pulling       // Getting remote ops
- applying      // Applying remote ops locally
- error         // Sync failed
- offline       // Device disconnected
- paused        // User paused sync
```

### Sync Triggers

1. Connectivity restored
2. App resumed from background
3. Periodic timer (15-30 minutes)
4. WebSocket `sync_available` event
5. Manual sync request

### Sync Flow

```
1. PUSH PHASE
   - Query local oplog: SELECT * FROM oplog WHERE synced = 0 ORDER BY timestamp ASC
   - For each operation:
     - Send to server via POST /sync/push
     - On success: Mark synced = 1, store serverTimestamp
     - On failure: Stop push, enter error state

2. PULL PHASE
   - Send GET /sync/pull with last cursor and deviceId
   - Receive operations array
   - For each operation:
     - Apply to local database with conflict resolution
   - Update cursor
   - If hasMore, repeat pull
```

### Backoff Strategy

```javascript
const backoffConfig = {
  initialDelay: 1000,    // 1 second
  maxDelay: 60000,       // 60 seconds
  multiplier: 2.0,
  maxRetries: 5
};

function calculateBackoff(attempt) {
  const delay = Math.min(
    backoffConfig.initialDelay * Math.pow(backoffConfig.multiplier, attempt),
    backoffConfig.maxDelay
  );
  return delay + Math.random() * 1000; // Add jitter
}
```

---

## 8. Conflict Resolution

### Conflict Detection

Conflict exists when:
- Same `entityId`
- Incoming `version` <= local `version`

### Resolution Matrix

| Scenario | Resolution |
|----------|------------|
| Delete vs Update | **Delete wins** |
| Update vs Update | Higher `updatedAt` wins |
| Same timestamp | Higher `version` wins |
| Same timestamp + version | Local wins (deterministic tie-breaker) |
| Block conflict | Last writer wins (NO auto-merge) |

### Important Rules

1. **Never auto-merge rich text** - Block content is replaced entirely
2. **Delete is permanent** - `deleted` only transitions `false -> true`
3. **Version increments on every mutation**
4. **Soft delete only** - Never remove documents

### Resolution Implementation

```javascript
function resolveConflict({ localVersion, localUpdatedAt, remoteVersion, remoteUpdatedAt, remoteIsDelete }) {
  // Check if this is a conflict
  const isConflict = remoteVersion <= localVersion;

  if (!isConflict) {
    return { useRemote: true, hadConflict: false, reason: 'No conflict' };
  }

  // Rule 1: Delete always wins
  if (remoteIsDelete) {
    return { useRemote: true, hadConflict: true, reason: 'Delete wins' };
  }

  // Rule 2: Compare timestamps
  if (remoteUpdatedAt > localUpdatedAt) {
    return { useRemote: true, hadConflict: true, reason: 'Remote newer' };
  }
  if (remoteUpdatedAt < localUpdatedAt) {
    return { useRemote: false, hadConflict: true, reason: 'Local newer' };
  }

  // Rule 3: Same timestamp - compare versions
  if (remoteVersion > localVersion) {
    return { useRemote: true, hadConflict: true, reason: 'Remote higher version' };
  }
  if (remoteVersion < localVersion) {
    return { useRemote: false, hadConflict: true, reason: 'Local higher version' };
  }

  // Tie-breaker: Local wins
  return { useRemote: false, hadConflict: true, reason: 'Local wins by default' };
}
```

### Conflict Logging

Log all conflicts for debugging:

```javascript
{
  "entityType": "note_block",
  "entityId": "block_uuid",
  "localVersion": 5,
  "remoteVersion": 5,
  "localUpdatedAt": 1700000000,
  "remoteUpdatedAt": 1700000000,
  "resolution": "local",
  "reason": "Local wins by default",
  "timestamp": "2024-01-15T10:30:00Z"
}
```

---

## 9. Real-time Updates

### WebSocket Connection

```
WS /sync/ws?token=<jwt_token>&deviceId=<device_uuid>
```

### Server Messages

```javascript
// New data available - client should pull
{ "type": "sync_available" }

// Keepalive ping (every 30 seconds)
{ "type": "ping" }

// Error notification
{ "type": "error", "message": "Session expired" }
```

### Client Messages

```javascript
// Response to ping
{ "type": "pong" }

// Subscribe to updates (if not in token)
{ "type": "subscribe", "userId": "user_uuid" }
```

### Important Rules

1. **Client NEVER trusts payload directly** - Always re-sync via pull
2. `sync_available` just triggers a pull - no data in the message
3. Ensures all data goes through conflict resolution
4. Reconnect with exponential backoff on disconnect

### MongoDB Change Streams Integration

```javascript
async function setupChangeStream(wsConnections) {
  const watchedCollections = ['folders', 'notes', 'note_blocks', 'prayers', 'promises', 'people', 'songs'];

  for (const collectionName of watchedCollections) {
    const collection = db.collection(collectionName);
    const changeStream = collection.watch([
      { $match: { 'operationType': { $in: ['insert', 'update', 'replace'] } } }
    ]);

    changeStream.on('change', async (change) => {
      const userId = change.fullDocument?.userId;
      const sourceDeviceId = change.fullDocument?.lastModifiedBy;

      if (!userId) return;

      // Find all WebSocket connections for this user
      const connections = wsConnections.get(userId) || [];

      // Notify each connection (except the one that made the change)
      for (const conn of connections) {
        if (conn.deviceId !== sourceDeviceId && conn.readyState === WebSocket.OPEN) {
          conn.send(JSON.stringify({ type: 'sync_available' }));
        }
      }
    });
  }
}
```

---

## 10. Error Handling

### Error Codes

| Code | HTTP Status | Description |
|------|-------------|-------------|
| `AUTH_REQUIRED` | 401 | Missing authentication token |
| `AUTH_INVALID` | 401 | Invalid or expired token |
| `FORBIDDEN` | 403 | User doesn't own this entity |
| `NOT_FOUND` | 404 | Entity not found |
| `VERSION_CONFLICT` | 409 | Entity version conflict |
| `VALIDATION_ERROR` | 400 | Invalid request data |
| `RATE_LIMITED` | 429 | Too many requests |
| `PAYLOAD_TOO_LARGE` | 413 | Request payload too large |
| `INTERNAL_ERROR` | 500 | Server error |

### Error Response Format

```json
{
  "success": false,
  "error": "ERROR_CODE",
  "message": "Human-readable message",
  "details": { }  // Optional additional info
}
```

### Handling Specific Errors

**VERSION_CONFLICT (409)**
```json
{
  "success": false,
  "error": "VERSION_CONFLICT",
  "currentVersion": 6,
  "message": "Entity has been modified by another device"
}
```

Client should:
1. Pull latest version
2. Apply conflict resolution
3. Retry push with resolved data

---

## 11. Security

### Security Rules

1. **All endpoints require authentication** (except `/auth/register`, `/auth/login`)
2. **Users can only access their own data** - Always filter by `userId`
3. **Rate limiting** - 100 requests per minute per user
4. **Maximum payload size** - 1MB per request
5. **Maximum operations per batch** - 100
6. **Input validation** - Validate all input against schemas
7. **HTTPS only** in production

### Validation Rules

#### Entity Fields

```javascript
// All entities must have:
const requiredFields = ['id', 'updatedAt', 'version', 'deleted', 'createdAt'];

// INSERT validation:
// - Entity must not exist
// - All required fields present
// - version must be 1
// - deleted must be false

// UPDATE validation:
// - Entity must exist
// - userId must match owner
// - Cannot update id, createdAt, userId

// DELETE validation:
// - Entity must exist
// - userId must match owner
// - Sets deleted = true only
```

### Rate Limiting

```javascript
// Using Redis for rate limiting
const rateLimiter = {
  windowMs: 60000,  // 1 minute
  maxRequests: 100,
  keyPrefix: 'ratelimit:'
};

async function checkRateLimit(userId) {
  const key = `${rateLimiter.keyPrefix}${userId}`;
  const current = await redis.incr(key);

  if (current === 1) {
    await redis.expire(key, rateLimiter.windowMs / 1000);
  }

  return current <= rateLimiter.maxRequests;
}
```

---

## 12. Deployment

### Environment Variables

```bash
# Server
PORT=3000
NODE_ENV=production

# MongoDB
MONGODB_URI=mongodb+srv://user:pass@cluster.mongodb.net/selah-prod
MONGODB_DB_NAME=selah-prod

# JWT
JWT_SECRET=your-256-bit-secret-key
JWT_ACCESS_EXPIRY=1h
JWT_REFRESH_EXPIRY=30d

# Redis (optional)
REDIS_URL=redis://localhost:6379

# Rate Limiting
RATE_LIMIT_WINDOW_MS=60000
RATE_LIMIT_MAX_REQUESTS=100
```

### Health Check Endpoint

```http
GET /health

Response (200 OK):
{
  "status": "healthy",
  "version": "1.0.0",
  "uptime": 86400,
  "database": "connected"
}
```

### Monitoring

Log the following events:
- All API requests (method, path, status, duration)
- Authentication events (login, logout, token refresh)
- Sync operations (push count, pull count, conflicts)
- Errors (with stack traces in non-production)

### Database Migrations

For schema changes:
1. Add new fields with defaults
2. Backfill existing documents
3. Remove deprecated fields later

Never remove fields that clients might still send.

### Scaling Considerations

1. **Horizontal scaling**: Stateless API servers behind load balancer
2. **MongoDB replica set**: For high availability
3. **WebSocket**: Use Redis pub/sub for multi-server WebSocket coordination
4. **CDN**: For static assets and potential read caching

---

## Quick Start Checklist

- [ ] Set up MongoDB Atlas cluster
- [ ] Create database and collections with indexes
- [ ] Implement authentication endpoints
- [ ] Implement push/push-batch endpoints
- [ ] Implement pull endpoint
- [ ] Set up WebSocket server
- [ ] Configure MongoDB Change Streams
- [ ] Add rate limiting
- [ ] Set up logging and monitoring
- [ ] Configure HTTPS
- [ ] Deploy and test sync flow

---

## File References

Client-side implementation files for reference:
- [sync_endpoints.dart](../lib/core/sync/server/sync_endpoints.dart) - API contract specification
- [mongodb_schema.dart](../lib/core/sync/server/mongodb_schema.dart) - MongoDB schema spec
- [conflict_resolver.dart](../lib/core/sync/engine/conflict_resolver.dart) - Conflict resolution logic
- [oplog_entry.dart](../lib/core/sync/models/oplog_entry.dart) - Operation log structure
- [auth_service.dart](../lib/core/sync/services/auth_service.dart) - Client auth handling
