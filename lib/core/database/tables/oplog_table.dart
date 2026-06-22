import 'package:drift/drift.dart';

/// Operation types for the oplog
///
/// Per spec: Every mutation is exactly one of these operations
class OperationType {
  static const String insert = 'INSERT';
  static const String update = 'UPDATE';
  static const String delete = 'DELETE';
}

/// Entity types tracked in the oplog
class EntityType {
  static const String folder = 'folder';
  static const String note = 'note';
  static const String noteBlock = 'note_block';
  static const String habitLog = 'habit_log';
}

/// Oplog table schema (THE HEART of sync)
///
/// Per spec section 3.6:
/// Non-negotiable rules:
/// 1. Every mutation creates exactly one oplog entry
/// 2. Oplog entries are immutable
/// 3. Never delete oplog rows (only mark synced)
///
/// This table is the source of truth for what needs to sync.
/// The sync engine reads unsynced entries and pushes them to the server.
class Oplog extends Table {
  /// Primary key - unique operation ID (UUID)
  TextColumn get opId => text()();

  /// Type of entity being modified (folder, note, note_block)
  TextColumn get entityType => text()();

  /// ID of the entity being modified
  TextColumn get entityId => text()();

  /// Type of operation (INSERT, UPDATE, DELETE)
  TextColumn get operation => text()();

  /// Full payload as JSON
  /// Contains the complete entity state at time of operation
  /// This ensures operations are replayable
  TextColumn get payloadJson => text()();

  /// Timestamp when operation was created (Unix milliseconds)
  /// Used for ordering during push
  IntColumn get timestamp => integer()();

  /// Device that created this operation
  /// Used for debugging and conflict attribution
  TextColumn get deviceId => text()();

  /// Sync status (0 = pending, 1 = synced)
  /// Only transitions from 0 to 1, never back
  IntColumn get synced => integer().withDefault(const Constant(0))();

  /// Version of the entity at time of operation
  /// Helps with conflict detection
  IntColumn get entityVersion => integer()();

  /// Optional: Server-assigned timestamp after sync
  /// NULL until synced
  IntColumn get serverTimestamp => integer().nullable()();

  /// Timestamp when this op was quarantined due to a permanent push failure.
  /// NULL while the op is healthy. Non-null ops are excluded from push.
  IntColumn get failedAt => integer().nullable()();

  /// Human-readable reason the op was quarantined (e.g. "VALIDATION_ERROR").
  /// NULL while the op is healthy.
  TextColumn get failedReason => text().nullable()();

  @override
  Set<Column> get primaryKey => {opId};
}
