import 'package:drift/drift.dart';

/// Sync-enabled table for Bible verse highlights.
///
/// Added sync fields (userId, version, deleted) in schema v26 so highlights
/// survive device changes. Flutter-only entity type pending Worker support
/// (same pattern as feedbackThread/feedbackMessage).
class BibleHighlights extends Table {
  /// Unique ID (UUID)
  TextColumn get id => text()();

  /// Owner user ID
  TextColumn get userId => text().withDefault(const Constant(''))();

  /// Book ID (1..66, matches bible_books.id in bible.db)
  IntColumn get bookId => integer()();

  /// Chapter number
  IntColumn get chapter => integer()();

  /// Start verse number (inclusive)
  IntColumn get verseStart => integer()();

  /// End verse number (inclusive, same as verseStart for single verse)
  IntColumn get verseEnd => integer()();

  /// Highlight color name from preset palette
  /// One of: 'yellow', 'green', 'blue', 'pink', 'orange', 'purple'
  TextColumn get color => text()();

  /// Optional user note attached to this highlight
  TextColumn get note => text().withDefault(const Constant(''))();

  /// Version for optimistic concurrency (starts at 1, increments on each update)
  IntColumn get version => integer().withDefault(const Constant(1))();

  /// Soft delete flag (0 = active, 1 = deleted)
  IntColumn get deleted => integer().withDefault(const Constant(0))();

  /// When this highlight was created (Unix ms)
  IntColumn get createdAt => integer()();

  /// When this highlight was last modified (Unix ms)
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}
