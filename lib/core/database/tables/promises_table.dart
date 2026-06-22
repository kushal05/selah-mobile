import 'package:drift/drift.dart';

/// Promises table schema
/// Stores Bible promises/verses with user notes
///
/// Per spec: soft delete only - no hard deletes
class Promises extends Table {
  /// Primary key - stable UUID (never changes)
  TextColumn get id => text()();

  /// Owner user ID
  TextColumn get userId => text()();

  /// Bible reference (e.g., "Jeremiah 29:11")
  TextColumn get reference => text()();

  /// Full verse/promise text
  TextColumn get content => text()();

  /// Short preview text for list display
  TextColumn get preview => text().withDefault(const Constant(''))();

  /// User's personal notes about this promise
  TextColumn get notes => text().withDefault(const Constant(''))();

  /// Optional category/tag
  TextColumn get category => text().nullable()();

  /// Whether this is a favorite promise
  IntColumn get isFavorite => integer().withDefault(const Constant(0))();

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
