import 'package:drift/drift.dart';

/// Song-Tag junction table for sync-enabled database
///
/// Each row has its own stable ID for oplog tracking.
/// Follows the standard sync entity pattern with soft deletes and versioning.
class SyncSongTags extends Table {
  TextColumn get id => text()();
  TextColumn get songId => text()();
  TextColumn get tagId => text()();
  TextColumn get userId => text()();
  IntColumn get updatedAt => integer()();
  IntColumn get version => integer().withDefault(const Constant(1))();
  IntColumn get deleted => integer().withDefault(const Constant(0))();

  /// Timestamp when moved to trash (Unix milliseconds, null = not trashed)
  IntColumn get trashedAt => integer().nullable()();

  IntColumn get createdAt => integer()();

  /// How strongly the song carries the tag, for ranking search: 3 a central
  /// theme, 2 a clear theme, 1 present but minor. 2 for links made in the app.
  IntColumn get weight => integer().withDefault(const Constant(2))();

  @override
  Set<Column> get primaryKey => {id};
}
