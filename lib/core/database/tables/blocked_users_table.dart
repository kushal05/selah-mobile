import 'package:drift/drift.dart';

/// Blocked users table
class BlockedUsers extends Table {
  /// Primary key - UUID
  TextColumn get id => text()();

  /// Owner user ID (who blocked)
  TextColumn get userId => text()();

  /// Blocked user's ID
  TextColumn get blockedUserId => text()();

  /// Blocked user's username (denormalized)
  TextColumn get blockedUsername => text()();

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
