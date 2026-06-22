import 'package:drift/drift.dart';

/// Note blocks table schema (the content layer)
///
/// Per spec section 3.5:
/// - Enables partial updates
/// - Smaller sync payloads
/// - Better conflict isolation
///
/// Block-based architecture means:
/// - Each block syncs independently
/// - Typing in one block doesn't affect others
/// - Conflict resolution happens at block level
class NoteBlocks extends Table {
  /// Primary key - stable UUID
  TextColumn get id => text()();

  /// Parent note ID
  TextColumn get noteId => text()();

  /// Block type (paragraph, heading, bullet, checkbox, etc.)
  /// Maps to BlockType enum in domain layer
  TextColumn get blockType => text()();

  /// Block content as JSON
  /// Contains formatted text spans, checked state, etc.
  TextColumn get contentJson => text()();

  /// Position within the note (0-indexed)
  /// Used for ordering blocks during render
  IntColumn get orderIndex => integer()();

  /// Last update timestamp (Unix milliseconds)
  IntColumn get updatedAt => integer()();

  /// Version number for optimistic locking
  IntColumn get version => integer().withDefault(const Constant(1))();

  /// Soft delete flag
  IntColumn get deleted => integer().withDefault(const Constant(0))();

  /// Timestamp when moved to trash (Unix milliseconds, null = not trashed)
  IntColumn get trashedAt => integer().nullable()();

  /// Creation timestamp (Unix milliseconds)
  IntColumn get createdAt => integer()();

  /// Note section ('main', 'personalApplication', 'prayer')
  /// Defaults to 'main' for backward compatibility with existing blocks
  TextColumn get section => text().withDefault(const Constant('main'))();

  @override
  Set<Column> get primaryKey => {id};
}
