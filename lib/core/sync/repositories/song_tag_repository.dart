import 'package:drift/drift.dart';

import '../../database/sync_database.dart';
import '../models/song_tag_model.dart';
import '../models/oplog_entry.dart';
import 'base_sync_repository.dart';

/// Repository for song-tag junction operations (sync-enabled)
class SongTagRepository extends BaseSyncRepository<SongTagModel> {
  final SyncDatabase _db;
  final String _deviceId;

  SongTagRepository(this._db, this._deviceId);

  @override
  String get deviceId => _deviceId;

  @override
  OplogEntityType get entityType => OplogEntityType.songTag;

  // ==================== READ OPERATIONS ====================

  /// Get all tag IDs for a song
  Future<List<String>> getTagIdsForSong(String songId) async {
    final query = _db.select(_db.syncSongTags)
      ..where((st) => st.songId.equals(songId) & st.deleted.equals(0) & st.trashedAt.isNull());

    final rows = await query.get();
    return rows.map((r) => r.tagId).toList();
  }

  /// Get all song-tag associations for a song
  Future<List<SongTagModel>> getTagsForSong(String songId) async {
    final query = _db.select(_db.syncSongTags)
      ..where((st) => st.songId.equals(songId) & st.deleted.equals(0) & st.trashedAt.isNull());

    final rows = await query.get();
    return rows.map(_toModel).toList();
  }

  /// Watch tag IDs for a song (reactive)
  Stream<List<String>> watchTagIdsForSong(String songId) {
    final query = _db.select(_db.syncSongTags)
      ..where((st) => st.songId.equals(songId) & st.deleted.equals(0) & st.trashedAt.isNull());

    return query.watch().map((rows) => rows.map((r) => r.tagId).toList());
  }

  /// Get all song IDs that have a specific tag
  Future<List<String>> getSongIdsWithTag(String tagId) async {
    final query = _db.select(_db.syncSongTags)
      ..where((st) => st.tagId.equals(tagId) & st.deleted.equals(0) & st.trashedAt.isNull());

    final rows = await query.get();
    return rows.map((r) => r.songId).toList();
  }

  // ==================== WRITE OPERATIONS ====================

  Future<SongTagModel> addTagToSong({
    required String songId,
    required String tagId,
    required String userId,
  }) async {
    // Check for existing (including soft-deleted) to prevent duplicates
    final existing = await (_db.select(_db.syncSongTags)
          ..where((st) =>
              st.songId.equals(songId) & st.tagId.equals(tagId)))
        .getSingleOrNull();

    if (existing != null && existing.deleted == 0) {
      return _toModel(existing);
    }

    final songTag = SongTagModel.create(
      id: existing?.id ?? generateId(),
      songId: songId,
      tagId: tagId,
      userId: userId,
    );

    final oplogEntry = createInsertOp(songTag);

    await _db.transaction(() async {
      await _db.into(_db.syncSongTags).insertOnConflictUpdate(_toCompanion(songTag));
      await _db.into(_db.oplog).insert(_oplogToCompanion(oplogEntry));
    });

    return songTag;
  }

  Future<void> removeTagFromSong(String songId, String tagId) async {
    final query = _db.select(_db.syncSongTags)
      ..where((st) =>
          st.songId.equals(songId) &
          st.tagId.equals(tagId) &
          st.deleted.equals(0));

    final row = await query.getSingleOrNull();
    if (row == null) return;

    final model = _toModel(row);
    final deleted = model.softDelete();
    final oplogEntry = createDeleteOp(deleted);

    await _db.transaction(() async {
      await (_db.update(_db.syncSongTags)..where((st) => st.id.equals(model.id)))
          .write(_toCompanion(deleted));
      await _db.into(_db.oplog).insert(_oplogToCompanion(oplogEntry));
    });
  }

  /// Replace all tags for a song with the given set.
  /// Diffs existing vs desired to minimize oplog entries.
  Future<void> setTagsForSong(
    String songId,
    List<String> tagIds,
    String userId,
  ) async {
    final current = await getTagsForSong(songId);
    final currentTagIds = current.map((st) => st.tagId).toSet();
    final desiredTagIds = tagIds.toSet();

    // Tags to add
    final toAdd = desiredTagIds.difference(currentTagIds);
    // Tags to remove
    final toRemove = currentTagIds.difference(desiredTagIds);

    for (final tagId in toAdd) {
      await addTagToSong(songId: songId, tagId: tagId, userId: userId);
    }
    for (final tagId in toRemove) {
      await removeTagFromSong(songId, tagId);
    }
  }

  // ==================== HELPERS ====================

  SongTagModel _toModel(SyncSongTag row) {
    return SongTagModel(
      id: row.id,
      songId: row.songId,
      tagId: row.tagId,
      userId: row.userId,
      updatedAt: row.updatedAt,
      version: row.version,
      deleted: row.deleted,
      trashedAt: row.trashedAt,
      createdAt: row.createdAt,
    );
  }

  SyncSongTagsCompanion _toCompanion(SongTagModel model) {
    return SyncSongTagsCompanion(
      id: Value(model.id),
      songId: Value(model.songId),
      tagId: Value(model.tagId),
      userId: Value(model.userId),
      updatedAt: Value(model.updatedAt),
      version: Value(model.version),
      deleted: Value(model.deleted),
      trashedAt: Value(model.trashedAt),
      createdAt: Value(model.createdAt),
    );
  }

  OplogCompanion _oplogToCompanion(OplogEntry entry) {
    return OplogCompanion(
      opId: Value(entry.opId),
      entityType: Value(entry.entityType.toDbValue()),
      entityId: Value(entry.entityId),
      operation: Value(entry.operation.toDbValue()),
      payloadJson: Value(entry.payloadJson),
      timestamp: Value(entry.timestamp),
      deviceId: Value(entry.deviceId),
      synced: Value(entry.synced ? 1 : 0),
      entityVersion: Value(entry.entityVersion),
      serverTimestamp: Value(entry.serverTimestamp),
    );
  }
}
