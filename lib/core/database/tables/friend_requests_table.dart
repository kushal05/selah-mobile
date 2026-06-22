import 'package:drift/drift.dart';

export '../../domain/enums/friend_enums.dart';

/// Pending, accepted, or rejected friend requests
class FriendRequests extends Table {
  /// Primary key - UUID
  TextColumn get id => text()();

  /// Owner user ID (who this record belongs to)
  TextColumn get userId => text()();

  /// User ID of the sender
  TextColumn get fromUserId => text()();

  /// Username of the sender (denormalized)
  TextColumn get fromUsername => text()();

  /// Display name of the sender (denormalized)
  TextColumn get fromDisplayName => text().withDefault(const Constant(''))();

  /// User ID of the recipient
  TextColumn get toUserId => text()();

  /// Username of the recipient (denormalized)
  TextColumn get toUsername => text()();

  /// Display name of the recipient (denormalized)
  TextColumn get toDisplayName => text().withDefault(const Constant(''))();

  /// Status: pending, accepted, rejected
  TextColumn get status => text().withDefault(const Constant('pending'))();

  /// Deterministic key for the user pair (sorted user IDs joined by _)
  TextColumn get userPairKey => text().nullable()();

  /// Last update timestamp (Unix milliseconds)
  IntColumn get updatedAt => integer()();

  /// Version number for optimistic locking
  IntColumn get version => integer().withDefault(const Constant(1))();

  /// Soft delete flag
  IntColumn get deleted => integer().withDefault(const Constant(0))();

  /// Creation timestamp (Unix milliseconds)
  IntColumn get createdAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}
