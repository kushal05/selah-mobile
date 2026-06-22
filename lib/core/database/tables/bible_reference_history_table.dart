import 'package:drift/drift.dart';

/// Bible reference history table schema
/// Tracks every Bible reference opened by the user with timestamps.
///
/// Per spec: soft delete only - no hard deletes
class BibleReferenceHistory extends Table {
  /// Primary key - stable UUID (never changes)
  TextColumn get id => text()();

  /// Owner user ID
  TextColumn get userId => text()();

  /// Book name (e.g., "John", "Genesis")
  TextColumn get book => text()();

  /// Chapter number
  IntColumn get chapter => integer()();

  /// Starting verse (nullable for chapter-only views)
  IntColumn get verseStart => integer().nullable()();

  /// Ending verse (nullable for single verse or chapter-only)
  IntColumn get verseEnd => integer().nullable()();

  /// Bible translation (e.g., "KJV", "NIV")
  TextColumn get translation => text()();

  /// Timestamp when the reference was opened (Unix milliseconds)
  IntColumn get openedAt => integer()();

  /// Last update timestamp (Unix milliseconds)
  IntColumn get updatedAt => integer()();

  /// Version number for optimistic locking
  IntColumn get version => integer().withDefault(const Constant(1))();

  /// Soft delete flag (0 = active, 1 = deleted)
  IntColumn get deleted => integer().withDefault(const Constant(0))();

  /// Creation timestamp (Unix milliseconds)
  IntColumn get createdAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}
