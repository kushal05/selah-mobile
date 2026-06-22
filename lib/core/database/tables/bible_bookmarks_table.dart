import 'package:drift/drift.dart';

/// Local-only table for Bible chapter bookmarks.
///
/// Lets users mark chapters for intentional re-reading (separate from
/// reading history which tracks what was already read).
/// Not synced — personal reading preference, device-local.
class BibleBookmarks extends Table {
  /// Unique ID (UUID)
  TextColumn get id => text()();

  /// Owner user ID
  TextColumn get userId => text()();

  /// Book ID (1..66)
  IntColumn get bookId => integer()();

  /// Book name (e.g. "John") — stored for display without joining bible.db
  TextColumn get bookName => text()();

  /// Chapter number
  IntColumn get chapter => integer()();

  /// Translation in use when the bookmark was created (e.g. "KJV")
  TextColumn get translation => text()();

  /// When bookmarked (Unix ms)
  IntColumn get createdAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}
