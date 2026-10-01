import 'package:drift/drift.dart';

/// Song-Folder junction table for sync-enabled database
///
/// Lets one song sit in several songbooks. `sync_songs.folder_id` stays the
/// song's primary songbook; a song's songbooks are that folder plus every live
/// row here. Each row has its own stable ID for oplog tracking.
class SyncSongFolders extends Table {
  TextColumn get id => text()();
  TextColumn get songId => text()();
  TextColumn get folderId => text()();
  TextColumn get userId => text()();
  IntColumn get updatedAt => integer()();
  IntColumn get version => integer().withDefault(const Constant(1))();
  IntColumn get deleted => integer().withDefault(const Constant(0))();

  /// Timestamp when moved to trash (Unix milliseconds, null = not trashed)
  IntColumn get trashedAt => integer().nullable()();

  IntColumn get createdAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}
