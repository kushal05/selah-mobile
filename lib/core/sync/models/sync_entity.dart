/// Base interface for all syncable entities
///
/// Per spec section 3.1:
/// Every table has: id, updatedAt, version, deleted
abstract class SyncEntity {
  /// Unique identifier (UUID)
  String get id;

  /// Last update timestamp (Unix milliseconds)
  int get updatedAt;

  /// Version number for optimistic locking
  int get version;

  /// Soft delete flag
  bool get isDeleted;

  /// Timestamp when moved to trash (null = not trashed)
  int? get trashedAt;

  /// Convert to JSON for oplog payload
  Map<String, dynamic> toJson();
}

/// Represents the result of a conflict resolution
class ConflictResolution<T extends SyncEntity> {
  final T winner;
  final T loser;
  final ConflictResolutionReason reason;

  const ConflictResolution({
    required this.winner,
    required this.loser,
    required this.reason,
  });
}

/// Reason for conflict resolution decision
enum ConflictResolutionReason {
  /// Local entity has higher updatedAt
  localNewer,

  /// Remote entity has higher updatedAt
  remoteNewer,

  /// Same timestamp, higher version wins
  higherVersion,

  /// Delete operation always wins
  deleteWins,

  /// Local wins by default (same timestamp and version)
  localDefault,
}
