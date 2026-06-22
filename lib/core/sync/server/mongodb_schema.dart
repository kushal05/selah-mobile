/// MongoDB Data Model Specification
///
/// Per spec section 6:
/// MongoDB mirrors local schema almost 1:1
///
/// Collections:
/// | Collection   | Purpose            |
/// | ------------ | ------------------ |
/// | folders      | Folder state       |
/// | notes        | Note state         |
/// | note_blocks  | Block state        |
/// | operations   | Optional audit log |
/// | sync_cursors | Per-device cursor  |
library;

// This file defines the MongoDB schema as Dart classes for documentation
// and validation. These are not used at runtime on the client but serve
// as the authoritative spec for the backend implementation.

/// MongoDB Folder document
///
/// Per spec section 6.2:
/// MongoDB mirrors local schema almost 1:1
///
/// ```json
/// {
///   "_id": "folder_123",
///   "parentId": null,
///   "name": "Sermons",
///   "userId": "user_456",
///   "updatedAt": 1700000000,
///   "version": 5,
///   "deleted": false,
///   "createdAt": 1699000000
/// }
/// ```
class MongoFolderSchema {
  /// Document structure
  static const schema = {
    '_id': 'string (UUID) - Primary key, matches local id',
    'parentId': 'string | null - Parent folder ID',
    'name': 'string - Folder name',
    'userId': 'string - Owner user ID',
    'updatedAt': 'int64 - Unix milliseconds',
    'version': 'int32 - Optimistic lock version',
    'deleted': 'bool - Soft delete flag',
    'createdAt': 'int64 - Unix milliseconds',
  };

  /// Required indexes
  static const indexes = [
    // Primary lookup by ID (automatic on _id)
    {'_id': 1},

    // List folders by user
    {'userId': 1, 'deleted': 1, 'name': 1},

    // List children of parent
    {'parentId': 1, 'deleted': 1},

    // Sync queries - find updated documents
    {'userId': 1, 'updatedAt': 1},
  ];

  /// Validation rules
  static const validationRules = '''
    - _id must be unique
    - name must be non-empty
    - name must be unique within parent (compound unique index)
    - userId must reference valid user
    - parentId if set must reference existing folder
    - version must be >= 1
    - updatedAt must be >= createdAt
  ''';
}

/// MongoDB Note document
///
/// Per spec section 6.2:
/// Note contains metadata only, content is in note_blocks
///
/// ```json
/// {
///   "_id": "note_789",
///   "folderId": "folder_123",
///   "userId": "user_456",
///   "title": "Sunday Sermon Notes",
///   "updatedAt": 1700000000,
///   "version": 12,
///   "deleted": false,
///   "createdAt": 1699000000,
///   "preacherId": "preacher_001",
///   "noteDate": 1699900000
/// }
/// ```
class MongoNoteSchema {
  static const schema = {
    '_id': 'string (UUID) - Primary key',
    'folderId': 'string - Parent folder ID',
    'userId': 'string - Owner user ID',
    'title': 'string - Note title',
    'updatedAt': 'int64 - Unix milliseconds',
    'version': 'int32 - Optimistic lock version',
    'deleted': 'bool - Soft delete flag',
    'createdAt': 'int64 - Unix milliseconds',
    'preacherId': 'string | null - Optional preacher reference',
    'noteDate': 'int64 | null - Optional associated date',
  };

  static const indexes = [
    {'_id': 1},

    // List notes in folder
    {'folderId': 1, 'deleted': 1, 'updatedAt': -1},

    // List notes by user
    {'userId': 1, 'deleted': 1, 'updatedAt': -1},

    // Sync queries
    {'userId': 1, 'updatedAt': 1},

    // Notes by preacher
    {'preacherId': 1, 'deleted': 1},

    // Full-text search on title
    {'title': 'text'},
  ];

  static const validationRules = '''
    - _id must be unique
    - folderId must reference existing folder
    - userId must reference valid user
    - title must be non-empty
    - version must be >= 1
  ''';
}

/// MongoDB NoteBlock document
///
/// Per spec section 6.2:
/// ```json
/// {
///   "_id": "block_123",
///   "noteId": "note_1",
///   "blockType": "paragraph",
///   "content": {...},
///   "orderIndex": 0,
///   "updatedAt": 1700000000,
///   "version": 12,
///   "deleted": false,
///   "createdAt": 1699000000
/// }
/// ```
class MongoNoteBlockSchema {
  static const schema = {
    '_id': 'string (UUID) - Primary key',
    'noteId': 'string - Parent note ID',
    'blockType': 'string - Block type enum',
    'content': 'object - Block content (varies by type)',
    'orderIndex': 'int32 - Position in note (0-indexed)',
    'updatedAt': 'int64 - Unix milliseconds',
    'version': 'int32 - Optimistic lock version',
    'deleted': 'bool - Soft delete flag',
    'createdAt': 'int64 - Unix milliseconds',
  };

  static const indexes = [
    {'_id': 1},

    // Get blocks for note in order
    {'noteId': 1, 'deleted': 1, 'orderIndex': 1},

    // Sync queries
    {'noteId': 1, 'updatedAt': 1},

    // Full-text search on content
    {'content.text': 'text'},
  ];

  static const blockTypes = [
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
    'image',
  ];

  static const validationRules = '''
    - _id must be unique
    - noteId must reference existing note
    - blockType must be valid enum value
    - content structure must match blockType
    - orderIndex must be >= 0
    - version must be >= 1
  ''';
}

/// MongoDB Operations collection (audit log)
///
/// Per spec section 6.1:
/// Optional audit log for debugging and analytics
class MongoOperationsSchema {
  static const schema = {
    '_id': 'string (op_id) - Operation UUID',
    'entityType': 'string - folder | note | note_block',
    'entityId': 'string - Entity UUID',
    'operation': 'string - INSERT | UPDATE | DELETE',
    'payload': 'object - Full entity state',
    'timestamp': 'int64 - Client timestamp',
    'serverTimestamp': 'int64 - Server receive timestamp',
    'deviceId': 'string - Source device',
    'userId': 'string - User who made change',
    'entityVersion': 'int32 - Version at time of op',
  };

  static const indexes = [
    // Idempotency check
    {'_id': 1},

    // Query ops by entity
    {'entityType': 1, 'entityId': 1, 'timestamp': 1},

    // Query ops by user (for sync)
    {'userId': 1, 'serverTimestamp': 1},

    // TTL index - expire after 90 days (optional)
    {'serverTimestamp': 1, 'expireAfterSeconds': 7776000},
  ];

  static const idempotencyRules = '''
    Per spec section 10:
    - Server uses op_id for idempotency
    - If op_id already exists, return success (no-op)
    - This handles partial push recovery
  ''';
}

/// MongoDB SyncCursors collection
///
/// Per spec section 6.1:
/// Per-device cursor tracking
class MongoSyncCursorsSchema {
  static const schema = {
    '_id': 'string - Compound: userId_deviceId',
    'userId': 'string - User ID',
    'deviceId': 'string - Device ID',
    'cursor': 'string - Opaque cursor position',
    'lastSyncAt': 'int64 - Last sync timestamp',
    'createdAt': 'int64 - First sync timestamp',
  };

  static const indexes = [
    {'_id': 1},
    {'userId': 1},
    {'deviceId': 1},
  ];
}

/// MongoDB Change Streams configuration
///
/// Per spec section 8:
/// Real-time updates via MongoDB Change Streams
class MongoChangeStreamsConfig {
  static const watchedCollections = [
    'folders',
    'notes',
    'note_blocks',
  ];

  static const pipeline = '''
    // Watch for changes relevant to user
    [
      {
        \$match: {
          'operationType': { \$in: ['insert', 'update', 'replace'] },
          'fullDocument.userId': '<user_id>'
        }
      }
    ]
  ''';

  static const eventFormat = '''
    When change detected:
    1. Extract userId from document
    2. Find active WebSocket connections for user
    3. Send notification: { type: 'sync_available' }
    4. Client will trigger pull (never send actual data)
  ''';
}
