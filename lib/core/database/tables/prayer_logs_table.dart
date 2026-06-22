import 'package:drift/drift.dart';

/// Prayer logs table schema
/// Records each time a user prays for a prayer item
///
/// Per spec: soft delete only - no hard deletes
class PrayerLogs extends Table {
  /// Primary key - stable UUID (never changes)
  TextColumn get id => text()();

  /// Reference to the prayer that was logged
  TextColumn get prayerId => text()();

  /// Owner user ID
  TextColumn get userId => text()();

  /// Optional note added when logging
  TextColumn get note => text().withDefault(const Constant(''))();

  /// Timestamp when the prayer was logged (Unix milliseconds)
  IntColumn get loggedAt => integer()();

  /// Date string for the session (YYYY-MM-DD) to group logs by day
  TextColumn get sessionDate => text()();

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
