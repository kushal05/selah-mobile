import 'package:drift/drift.dart';

/// Folders table schema
/// Stores folder hierarchy for organizing notes
///
/// Per spec: parent_id = NULL means root folder
/// Soft delete only - no hard deletes
class Folders extends Table {
  /// Primary key - stable UUID (never changes)
  TextColumn get id => text()();

  /// Parent folder ID (NULL for root folders)
  TextColumn get parentId => text().nullable()();

  /// Folder name (unique per parent)
  TextColumn get name => text()();

  /// Folder type: 'note' or 'song'
  TextColumn get type => text().withDefault(const Constant('note'))();

  /// Visibility level: 'personal', 'group', or 'open'
  TextColumn get visibility => text().withDefault(const Constant('personal'))();

  /// Group ID (only set when visibility = 'group')
  TextColumn get groupId => text().nullable()();

  /// Owner user ID
  TextColumn get userId => text()();

  /// Last update timestamp (Unix milliseconds)
  /// Used for conflict resolution
  IntColumn get updatedAt => integer()();

  /// Version number for optimistic locking
  /// Incremented on every mutation
  IntColumn get version => integer().withDefault(const Constant(1))();

  /// Soft delete flag (0 = active, 1 = deleted)
  /// Per spec: never hard delete
  IntColumn get deleted => integer().withDefault(const Constant(0))();

  /// Timestamp when moved to trash (Unix milliseconds, null = not trashed)
  IntColumn get trashedAt => integer().nullable()();

  /// Creation timestamp (Unix milliseconds)
  IntColumn get createdAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}
