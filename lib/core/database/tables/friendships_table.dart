import 'package:drift/drift.dart';

/// Active friendships between users
class Friendships extends Table {
  /// Primary key - UUID
  TextColumn get id => text()();

  /// Owner user ID
  TextColumn get userId => text()();

  /// Friend's user ID
  TextColumn get friendUserId => text()();

  /// Friend's username (denormalized for display)
  TextColumn get friendUsername => text()();

  /// Friend's display name (denormalized for display)
  TextColumn get friendDisplayName => text().withDefault(const Constant(''))();

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
