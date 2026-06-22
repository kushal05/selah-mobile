import 'package:drift/drift.dart';

/// Sync status values
class SyncStatus {
  static const String idle = 'idle';
  static const String pushing = 'pushing';
  static const String pulling = 'pulling';
  static const String error = 'error';
  static const String offline = 'offline';
}

/// Sync state table schema
///
/// Per spec section 3.7:
/// Stores sync cursors and status.
/// Single row table (id = 1 constraint).
///
/// This table tracks:
/// - When we last pushed to server
/// - When we last pulled from server
/// - Where we are in the server's change stream
/// - Current sync status
class SyncState extends Table {
  /// Primary key - always 1 (single row table)
  IntColumn get id => integer()();

  /// Timestamp of last successful push (Unix milliseconds)
  IntColumn get lastPushTimestamp => integer().nullable()();

  /// Timestamp of last successful pull (Unix milliseconds)
  IntColumn get lastPullTimestamp => integer().nullable()();

  /// Server-provided cursor for resuming pulls
  /// Opaque string - don't parse or modify
  TextColumn get lastRemoteCursor => text().nullable()();

  /// Current sync status (idle, pushing, pulling, error, offline)
  TextColumn get syncStatus => text().withDefault(const Constant('idle'))();

  /// Error message if syncStatus is 'error'
  TextColumn get lastError => text().nullable()();

  /// Number of consecutive sync failures (for backoff calculation)
  IntColumn get consecutiveFailures =>
      integer().withDefault(const Constant(0))();

  /// Timestamp of last sync attempt (successful or not)
  IntColumn get lastSyncAttempt => integer().nullable()();

  /// Number of pending (unsynced) operations
  /// Cached for quick UI display
  IntColumn get pendingOpsCount => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}
