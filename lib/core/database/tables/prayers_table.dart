import 'package:drift/drift.dart';

export '../../domain/enums/prayer_enums.dart';

/// Prayers table schema
/// Stores prayer requests with tracking and reminders
///
/// Per spec: soft delete only - no hard deletes
class Prayers extends Table {
  /// Primary key - stable UUID (never changes)
  TextColumn get id => text()();

  /// Owner user ID
  TextColumn get userId => text()();

  /// Prayer title/subject
  TextColumn get title => text()();

  /// Full prayer content/description
  TextColumn get content => text().withDefault(const Constant(''))();

  /// Prayer frequency for reminders
  TextColumn get frequency => text().withDefault(const Constant('daily'))();

  /// Prayer status (active, answered, archived)
  TextColumn get status => text().withDefault(const Constant('active'))();

  /// Optional category/tag
  TextColumn get category => text().nullable()();

  /// Reminder datetime (Unix milliseconds, nullable)
  IntColumn get reminderAt => integer().nullable()();

  /// When the prayer was answered (Unix milliseconds, nullable)
  IntColumn get answeredAt => integer().nullable()();

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

  /// Per-field update timestamps for field-level merge conflict resolution.
  /// JSON map of {fieldName: timestampMs}. Empty map '{}' for legacy entities.
  TextColumn get fieldUpdatedAt => text().withDefault(const Constant('{}'))();

  @override
  Set<Column> get primaryKey => {id};
}
