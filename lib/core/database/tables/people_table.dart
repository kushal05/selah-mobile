import 'package:drift/drift.dart';

/// People table schema
/// Stores people to pray for with contact info
///
/// Per spec: soft delete only - no hard deletes
class People extends Table {
  /// Primary key - stable UUID (never changes)
  TextColumn get id => text()();

  /// Owner user ID
  TextColumn get userId => text()();

  /// Person's name
  TextColumn get name => text()();

  /// Relationship/group (e.g., "Family", "Friend", "Church Member")
  TextColumn get relation => text().withDefault(const Constant(''))();

  /// Church or organization the person belongs to
  TextColumn get church => text().nullable()();

  /// Optional email address
  TextColumn get email => text().nullable()();

  /// Optional phone number
  TextColumn get phone => text().nullable()();

  /// Notes about this person or prayer requests for them
  TextColumn get notes => text().withDefault(const Constant(''))();

  /// Optional profile image URL or path
  TextColumn get imageUrl => text().nullable()();

  /// Last update timestamp (Unix milliseconds)
  IntColumn get updatedAt => integer()();

  /// Version number for optimistic locking
  IntColumn get version => integer().withDefault(const Constant(1))();

  /// Soft delete flag (0 = active, 1 = deleted)
  IntColumn get deleted => integer().withDefault(const Constant(0))();

  /// Timestamp when moved to trash (Unix milliseconds, null = not trashed)
  IntColumn get trashedAt => integer().nullable()();

  /// Creation timestamp (Unix milliseconds)
  IntColumn get createdAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}
