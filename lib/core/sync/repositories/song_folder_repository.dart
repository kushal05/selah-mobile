import 'package:drift/drift.dart';

import '../../database/sync_database.dart';
import '../models/song_folder_model.dart';
import '../models/oplog_entry.dart';
import 'base_sync_repository.dart';

/// A songbook a song belongs to, as shown on the song.
typedef Songbook = ({String id, String name});

/// Repository for song-folder junction operations (sync-enabled).
///
/// A song's songbooks are its `songs.folder_id` (the primary songbook) plus
/// every live row in sync_song_folders. Both are read together everywhere:
/// songs saved before memberships existed, or edited on a build without them,
/// only have `folder_id`.
class SongFolderRepository extends BaseSyncRepository<SongFolderModel> {
  final SyncDatabase _db;
  final String _deviceId;

  SongFolderRepository(this._db, this._deviceId);

  @override
  String get deviceId => _deviceId;

  @override
  OplogEntityType get entityType => OplogEntityType.songFolder;

  // ==================== READ OPERATIONS ====================

  /// Folder IDs of a song's live links (not including `songs.folder_id`).
  Future<List<String>> getLinkedFolderIds(String songId) async {
    final rows = await (_db.select(_db.syncSongFolders)
          ..where((sf) =>
              sf.songId.equals(songId) &
              sf.deleted.equals(0) &
              sf.trashedAt.isNull()))
        .get();
    return rows.map((r) => r.folderId).toSet().toList();
  }

  /// The songbooks to start the editor with: `folder_id` first, then the
  /// links. Songbooks in Trash are kept, so saving does not quietly drop them;
  /// permanently deleted ones are not, or the user could never remove a song
  /// from a songbook that no longer exists.
  Future<List<String>> getSongbookIdsForEditing(String songId) async {
    final rows = await _db.customSelect(
      'SELECT f.id, (f.id IS s.folder_id) AS is_primary '
      'FROM songs s JOIN folders f '
      'ON f.id = s.folder_id OR f.id IN ('
      '  SELECT folder_id FROM sync_song_folders '
      '  WHERE song_id = s.id AND deleted = 0 AND trashed_at IS NULL'
      ') '
      'WHERE s.id = ? AND f.deleted = 0 '
      'ORDER BY is_primary DESC, f.name COLLATE NOCASE',
      variables: [Variable.withString(songId)],
      readsFrom: {_db.songs, _db.folders, _db.syncSongFolders},
    ).get();
    return [for (final r in rows) r.read<String>('id')];
  }

  /// Watch a song's songbooks: its primary folder first, then the rest by
  /// name. Songbooks that are deleted or in Trash are left out, so a link to
  /// one needs no cascade when it goes.
  Stream<List<Songbook>> watchSongbooksForSong(String songId) {
    return _db.customSelect(
      'SELECT f.id, f.name, (f.id IS s.folder_id) AS is_primary '
      'FROM songs s JOIN folders f '
      'ON f.id = s.folder_id OR f.id IN ('
      '  SELECT folder_id FROM sync_song_folders '
      '  WHERE song_id = s.id AND deleted = 0 AND trashed_at IS NULL'
      ') '
      'WHERE s.id = ? AND f.deleted = 0 AND f.trashed_at IS NULL '
      'ORDER BY is_primary DESC, f.name COLLATE NOCASE',
      variables: [Variable.withString(songId)],
      readsFrom: {_db.songs, _db.folders, _db.syncSongFolders},
    ).watch().map((rows) => [
          for (final r in rows)
            (id: r.read<String>('id'), name: r.read<String>('name')),
        ]);
  }

  /// Watch every live link for a user, as song ID -> linked folder IDs.
  /// Callers union this with each song's `folderId`.
  Stream<Map<String, Set<String>>> watchLinksBySong(String userId) {
    final query = _db.select(_db.syncSongFolders)
      ..where((sf) =>
          sf.userId.equals(userId) &
          sf.deleted.equals(0) &
          sf.trashedAt.isNull());
    return query.watch().map((rows) {
      final bySong = <String, Set<String>>{};
      for (final r in rows) {
        (bySong[r.songId] ??= <String>{}).add(r.folderId);
      }
      return bySong;
    });
  }

  // ==================== WRITE OPERATIONS ====================

  /// Which folder `songs.folder_id` should hold once the song's songbooks are
  /// [chosen]. [live] is the songbooks the user can see; a chosen one outside
  /// it is in Trash.
  ///
  /// The current primary if it is still chosen and live, so editing other
  /// songbooks never reshuffles it. Otherwise the first live choice: a primary
  /// in Trash would leave the song in no visible songbook on builds that only
  /// read `folder_id`. Only when every choice is in Trash does one stay
  /// primary, so restoring it brings the song back.
  static String? choosePrimary(
    String? current,
    List<String> chosen, {
    required Set<String> live,
  }) {
    if (current != null && chosen.contains(current) && live.contains(current)) {
      return current;
    }
    for (final id in chosen) {
      if (live.contains(id)) return id;
    }
    if (current != null && chosen.contains(current)) return current;
    return chosen.isEmpty ? null : chosen.first;
  }

  Future<SongFolderModel> addSongToFolder({
    required String songId,
    required String folderId,
    required String userId,
  }) async {
    // Two devices can each link the same pair, so there may be several rows.
    final rows = await (_db.select(_db.syncSongFolders)
          ..where((sf) =>
              sf.songId.equals(songId) & sf.folderId.equals(folderId)))
        .get();

    for (final row in rows) {
      if (row.deleted == 0 && row.trashedAt == null) return _toModel(row);
    }

    final OplogEntry op;
    final SongFolderModel link;
    if (rows.isEmpty) {
      link = SongFolderModel.create(
        id: generateId(),
        songId: songId,
        folderId: folderId,
        userId: userId,
      );
      op = createInsertOp(link);
    } else {
      // Revive the newest dead row rather than adding another.
      rows.sort((a, b) => b.version.compareTo(a.version));
      link = _toModel(rows.first).revive();
      op = createUpdateOp(link);
    }

    await _db.transaction(() async {
      await _db.into(_db.syncSongFolders).insertOnConflictUpdate(_toCompanion(link));
      await _db.into(_db.oplog).insert(_oplogToCompanion(op));
    });
    return link;
  }

  /// Deletes every live row for the pair: two devices may each have made one.
  Future<void> removeSongFromFolder(String songId, String folderId) =>
      _deleteLinks((sf) =>
          sf.songId.equals(songId) &
          sf.folderId.equals(folderId) &
          sf.deleted.equals(0));

  /// Delete every link of a permanently deleted song. Left live, they would
  /// keep the server's GC from ever hard-deleting the song (it skips parents
  /// with live children).
  Future<void> deleteLinksForSong(String songId) => _deleteLinks(
      (sf) => sf.songId.equals(songId) & sf.deleted.equals(0));

  /// Delete every link into permanently deleted songbooks, for the same
  /// reason. Trashed songbooks keep theirs, so restoring one brings its songs
  /// back.
  Future<void> deleteLinksForFolders(Iterable<String> folderIds) {
    final ids = folderIds.toList();
    if (ids.isEmpty) return Future.value();
    return _deleteLinks(
        (sf) => sf.folderId.isIn(ids) & sf.deleted.equals(0));
  }

  Future<void> _deleteLinks(
    Expression<bool> Function($SyncSongFoldersTable sf) where,
  ) async {
    await _db.transaction(() async {
      final rows =
          await (_db.select(_db.syncSongFolders)..where(where)).get();
      for (final row in rows) {
        final deleted = _toModel(row).softDelete();
        await (_db.update(_db.syncSongFolders)
              ..where((sf) => sf.id.equals(deleted.id)))
            .write(_toCompanion(deleted));
        await _db
            .into(_db.oplog)
            .insert(_oplogToCompanion(createDeleteOp(deleted)));
      }
    });
  }

  /// Make the song's links exactly [folderIds], diffing against what is there
  /// so unchanged links produce no operations. Does not touch
  /// `songs.folder_id`; the caller saves that with the song (see
  /// [choosePrimary]).
  Future<void> setFoldersForSong(
    String songId,
    List<String> folderIds,
    String userId,
  ) async {
    final current = (await getLinkedFolderIds(songId)).toSet();
    final desired = folderIds.toSet();

    for (final folderId in desired.difference(current)) {
      await addSongToFolder(songId: songId, folderId: folderId, userId: userId);
    }
    for (final folderId in current.difference(desired)) {
      await removeSongFromFolder(songId, folderId);
    }
  }

  // ==================== HELPERS ====================

  SongFolderModel _toModel(SyncSongFolder row) {
    return SongFolderModel(
      id: row.id,
      songId: row.songId,
      folderId: row.folderId,
      userId: row.userId,
      updatedAt: row.updatedAt,
      version: row.version,
      deleted: row.deleted,
      trashedAt: row.trashedAt,
      createdAt: row.createdAt,
    );
  }

  SyncSongFoldersCompanion _toCompanion(SongFolderModel model) {
    return SyncSongFoldersCompanion(
      id: Value(model.id),
      songId: Value(model.songId),
      folderId: Value(model.folderId),
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
