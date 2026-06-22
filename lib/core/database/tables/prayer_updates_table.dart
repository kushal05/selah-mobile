import 'package:drift/drift.dart';

/// Prayer updates table schema
/// Stores structured updates for prayer items (previously encoded in prayer.content)
///
/// Per spec: soft delete only - no hard deletes
class PrayerUpdates extends Table {
  /// Primary key - stable UUID (never changes)
  TextColumn get id => text()();

  /// Reference to the parent prayer
  TextColumn get prayerId => text()();

  /// User who created this update
  TextColumn get userId => text()();

  /// Update text content
  TextColumn get content => text()();

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
