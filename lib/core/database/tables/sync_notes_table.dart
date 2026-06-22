import 'package:drift/drift.dart';

/// Notes table schema (metadata only - no content)
///
/// Per spec section 3.4:
/// - No content stored here
/// - Keeps note list fast
/// - Prevents massive row updates during typing
/// - Content is stored in note_blocks table
class SyncNotes extends Table {
  /// Primary key - stable UUID
  TextColumn get id => text()();

  /// Folder this note belongs to
  TextColumn get folderId => text()();

  /// Owner user ID
  TextColumn get userId => text()();

  /// Note title
  TextColumn get title => text()();

  /// Last update timestamp (Unix milliseconds)
  /// Used for conflict resolution
  IntColumn get updatedAt => integer()();

  /// Version number for optimistic locking
  IntColumn get version => integer().withDefault(const Constant(1))();

  /// Soft delete flag (0 = active, 1 = deleted)
  IntColumn get deleted => integer().withDefault(const Constant(0))();

  /// Timestamp when moved to trash (Unix milliseconds, null = not trashed)
  IntColumn get trashedAt => integer().nullable()();

  /// Creation timestamp (Unix milliseconds)
  IntColumn get createdAt => integer()();

  /// Optional preacher reference (for sermon notes)
  TextColumn get preacherId => text().nullable()();

  /// Optional date associated with note (e.g., sermon date)
  IntColumn get noteDate => integer().nullable()();

  /// Per-field update timestamps for field-level merge conflict resolution.
  /// JSON map of {fieldName: timestampMs}. Empty map '{}' for legacy entities.
  TextColumn get fieldUpdatedAt =>
      text().withDefault(const Constant('{}'))();

  /// JSON snapshot of the full block list for fast single-read access.
  /// Null until first save or migration backfill.
  TextColumn get documentJson => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  String get tableName => 'sync_notes';
}
