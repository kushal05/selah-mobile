import 'package:uuid/uuid.dart';

import '../models/oplog_entry.dart';
import '../models/sync_entity.dart';

/// Base class for all sync-enabled repositories
///
/// Per spec section 4:
/// Every write MUST:
/// - Occur in a transaction
/// - Update updatedAt + version
/// - Create an oplog entry
///
/// This base class provides the oplog creation logic that all
/// repositories must use.
abstract class BaseSyncRepository<T extends SyncEntity> {
  static const _uuid = Uuid();

  /// Current device ID (set by DeviceService)
  String get deviceId;

  /// Entity type for oplog entries
  OplogEntityType get entityType;

  /// Generate a new UUID
  String generateId() => _uuid.v4();

  /// Generate a new operation ID
  String generateOpId() => _uuid.v4();

  /// Create an INSERT oplog entry
  ///
  /// Per spec: Every mutation creates exactly one oplog entry
  OplogEntry createInsertOp(T entity) {
    return OplogEntry.insert(
      opId: generateOpId(),
      entityType: entityType,
      entityId: entity.id,
      payload: entity.toJson(),
      deviceId: deviceId,
      entityVersion: entity.version,
    );
  }

  /// Create an UPDATE oplog entry
  OplogEntry createUpdateOp(T entity) {
    return OplogEntry.update(
      opId: generateOpId(),
      entityType: entityType,
      entityId: entity.id,
      payload: entity.toJson(),
      deviceId: deviceId,
      entityVersion: entity.version,
    );
  }

  /// Create a DELETE oplog entry
  ///
  /// Per spec: Delete is soft delete (deleted = 1)
  /// The payload contains the full entity state for potential undo
  OplogEntry createDeleteOp(T entity) {
    return OplogEntry.delete(
      opId: generateOpId(),
      entityType: entityType,
      entityId: entity.id,
      payload: entity.toJson(),
      deviceId: deviceId,
      entityVersion: entity.version,
    );
  }
}

/// Batch size for editor input
///
/// Per spec section 4.1:
/// Editor batches input (300-500ms) before writing
class EditorBatchConfig {
  /// Minimum time between writes (milliseconds)
  static const int minBatchInterval = 300;

  /// Maximum time between writes (milliseconds)
  static const int maxBatchInterval = 500;

  /// Default batch interval (milliseconds)
  static const int defaultBatchInterval = 400;
}
