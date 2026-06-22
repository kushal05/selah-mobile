import 'package:drift/drift.dart';

import '../../database/sync_database.dart';
import '../models/oplog_entry.dart';
import '../models/song_model.dart';
import 'base_sync_repository.dart';
import 'entity_access_repository.dart';

/// Repository for song operations
///
/// Per spec: Every write is transactional with oplog entry
class SongRepository extends BaseSyncRepository<SongModel> {
  final SyncDatabase _db;
  final String _deviceId;
  final EntityAccessRepository _entityAccessRepo;

  SongRepository(this._db, this._deviceId, this._entityAccessRepo);

  @override
  String get deviceId => _deviceId;

  @override
  OplogEntityType get entityType => OplogEntityType.song;

  // ==================== READ OPERATIONS ====================

  /// Get all songs (non-deleted) for a user
  Future<List<SongModel>> getAllSongs(String userId) async {
    final query = _db.select(_db.songs)
      ..where((s) => s.deleted.equals(0) & s.trashedAt.isNull() & s.userId.equals(userId))
      ..orderBy([(s) => OrderingTerm.asc(s.title)]);

    final rows = await query.get();
    return rows.map(_toModel).toList();
  }

  /// Get songs in a folder for a user
  Future<List<SongModel>> getSongsInFolder(String? folderId, String userId) async {
    final query = _db.select(_db.songs)
      ..where((s) => s.deleted.equals(0) & s.trashedAt.isNull() & s.userId.equals(userId))
      ..orderBy([(s) => OrderingTerm.asc(s.title)]);

    if (folderId == null) {
      query.where((s) => s.folderId.isNull());
    } else {
      query.where((s) => s.folderId.equals(folderId));
    }

    final rows = await query.get();
    return rows.map(_toModel).toList();
  }

  /// Get favorite songs for a user
  Future<List<SongModel>> getFavoriteSongs(String userId) async {
    final query = _db.select(_db.songs)
      ..where((s) => s.deleted.equals(0) & s.trashedAt.isNull() & s.userId.equals(userId) & s.isFavorite.equals(1))
      ..orderBy([(s) => OrderingTerm.asc(s.title)]);

    final rows = await query.get();
    return rows.map(_toModel).toList();
  }

  /// Get songs by language for a user
  Future<List<SongModel>> getSongsByLanguage(String language, String userId) async {
    final query = _db.select(_db.songs)
      ..where((s) => s.deleted.equals(0) & s.trashedAt.isNull() & s.userId.equals(userId) & s.language.equals(language))
      ..orderBy([(s) => OrderingTerm.asc(s.title)]);

    final rows = await query.get();
    return rows.map(_toModel).toList();
  }

  /// Get songs with chords for a user
  Future<List<SongModel>> getSongsWithChords(String userId) async {
    final query = _db.select(_db.songs)
      ..where((s) => s.deleted.equals(0) & s.trashedAt.isNull() & s.userId.equals(userId) & s.hasChords.equals(1))
      ..orderBy([(s) => OrderingTerm.asc(s.title)]);

    final rows = await query.get();
    return rows.map(_toModel).toList();
  }

  /// Get song by ID
  Future<SongModel?> getSongById(String id) async {
    final query = _db.select(_db.songs)..where((s) => s.id.equals(id));

    final row = await query.getSingleOrNull();
    return row != null ? _toModel(row) : null;
  }

  /// Search songs by title or lyrics for a user
  Future<List<SongModel>> searchSongs(String query, String userId) async {
    final escaped = _escapeLikePattern(query);
    final pattern = '%$escaped%';
    final rows = await _db.customSelect(
      'SELECT * FROM songs WHERE deleted = 0 AND trashed_at IS NULL AND user_id = ? '
      "AND (title LIKE ? ESCAPE '\\' OR lyrics LIKE ? ESCAPE '\\' OR tags LIKE ? ESCAPE '\\') "
      'ORDER BY title ASC',
      variables: [
        Variable.withString(userId),
        Variable.withString(pattern),
        Variable.withString(pattern),
        Variable.withString(pattern),
      ],
    ).get();
    return rows.map((row) {
      return SongModel(
        id: row.read<String>('id'),
        userId: row.read<String>('user_id'),
        title: row.read<String>('title'),
        folderId: row.readNullable<String>('folder_id'),
        lyrics: row.read<String>('lyrics'),
        chords: row.read<String>('chords'),
        scale: row.read<String>('scale'),
        chordLinesJson: row.read<String>('chord_lines'),
        language: row.read<String>('language'),
        book: row.readNullable<String>('book'),
        preview: row.read<String>('preview'),
        tags: row.read<String>('tags'),
        notes: row.read<String>('notes'),
        hasChords: row.read<int>('has_chords') == 1,
        isFavorite: row.read<int>('is_favorite') == 1,
        updatedAt: row.read<int>('updated_at'),
        version: row.read<int>('version'),
        deleted: row.read<int>('deleted'),
        createdAt: row.read<int>('created_at'),
      );
    }).toList();
  }

  /// Advanced song search with combinable filters.
  /// All filters are optional and applied via AND logic.
  /// Tag filtering uses the sync_song_tags junction table (tag IDs).
  Future<List<SongModel>> searchSongsFiltered({
    required String userId,
    String? textQuery,
    List<String>? tagIds,
    String? scale,
    String? folderId,
    List<String>? folderIds,
  }) async {
    // Build dynamic WHERE clauses
    final conditions = <String>["s.deleted = 0", "s.trashed_at IS NULL", "s.user_id = ?"];
    final variables = <Variable>[Variable.withString(userId)];

    if (textQuery != null && textQuery.trim().isNotEmpty) {
      final escaped = _escapeLikePattern(textQuery.trim());
      final pattern = '%$escaped%';
      conditions.add("(s.title LIKE ? ESCAPE '\\' OR s.lyrics LIKE ? ESCAPE '\\')");
      variables.add(Variable.withString(pattern));
      variables.add(Variable.withString(pattern));
    }

    if (scale != null && scale.isNotEmpty) {
      conditions.add("s.scale = ?");
      variables.add(Variable.withString(scale));
    }

    if (folderId != null) {
      if (folderIds != null && folderIds.isNotEmpty) {
        // Subtree filter: include the target folder and all descendants
        final placeholders = folderIds.map((_) => '?').join(', ');
        conditions.add("s.folder_id IN ($placeholders)");
        for (final id in folderIds) {
          variables.add(Variable.withString(id));
        }
      } else {
        conditions.add("s.folder_id = ?");
        variables.add(Variable.withString(folderId));
      }
    }

    // Tag filter: uses the sync_song_tags junction table (match any)
    if (tagIds != null && tagIds.isNotEmpty) {
      final placeholders = tagIds.map((_) => '?').join(', ');
      conditions.add(
        "s.id IN (SELECT song_id FROM sync_song_tags WHERE tag_id IN ($placeholders) AND deleted = 0)",
      );
      for (final tagId in tagIds) {
        variables.add(Variable.withString(tagId));
      }
    }

    final whereClause = conditions.join(' AND ');
    final sql = 'SELECT s.* FROM songs s WHERE $whereClause ORDER BY s.title ASC';

    final rows = await _db.customSelect(sql, variables: variables).get();
    return rows.map((row) {
      return SongModel(
        id: row.read<String>('id'),
        userId: row.read<String>('user_id'),
        title: row.read<String>('title'),
        folderId: row.readNullable<String>('folder_id'),
        lyrics: row.read<String>('lyrics'),
        chords: row.read<String>('chords'),
        scale: row.read<String>('scale'),
        chordLinesJson: row.read<String>('chord_lines'),
        language: row.read<String>('language'),
        book: row.readNullable<String>('book'),
        preview: row.read<String>('preview'),
        tags: row.read<String>('tags'),
        notes: row.read<String>('notes'),
        hasChords: row.read<int>('has_chords') == 1,
        isFavorite: row.read<int>('is_favorite') == 1,
        updatedAt: row.read<int>('updated_at'),
        version: row.read<int>('version'),
        deleted: row.read<int>('deleted'),
        createdAt: row.read<int>('created_at'),
      );
    }).toList();
  }

  /// Watch all songs (reactive stream) for a user
  Stream<List<SongModel>> watchAllSongs(String userId) {
    final query = _db.select(_db.songs)
      ..where((s) => s.deleted.equals(0) & s.trashedAt.isNull() & s.userId.equals(userId))
      ..orderBy([(s) => OrderingTerm.asc(s.title)]);

    return query.watch().map((rows) => rows.map(_toModel).toList());
  }

  /// Watch songs in folder for a user
  Stream<List<SongModel>> watchSongsInFolder(String? folderId, String userId) {
    var query = _db.select(_db.songs)
      ..where((s) => s.deleted.equals(0) & s.trashedAt.isNull() & s.userId.equals(userId))
      ..orderBy([(s) => OrderingTerm.asc(s.title)]);

    if (folderId == null) {
      query = query..where((s) => s.folderId.isNull());
    } else {
      query = query..where((s) => s.folderId.equals(folderId));
    }

    return query.watch().map((rows) => rows.map(_toModel).toList());
  }

  /// Watch a single song by ID (reactive stream)
  Stream<SongModel?> watchSongById(String id) {
    final query = _db.select(_db.songs)..where((s) => s.id.equals(id));
    return query.watchSingleOrNull().map((row) => row != null ? _toModel(row) : null);
  }

  /// Watch favorite songs for a user
  Stream<List<SongModel>> watchFavoriteSongs(String userId) {
    final query = _db.select(_db.songs)
      ..where((s) => s.deleted.equals(0) & s.trashedAt.isNull() & s.userId.equals(userId) & s.isFavorite.equals(1))
      ..orderBy([(s) => OrderingTerm.asc(s.title)]);

    return query.watch().map((rows) => rows.map(_toModel).toList());
  }

  /// Get unique languages for a user
  Future<List<String>> getUniqueLanguages(String userId) async {
    final result = await _db.customSelect(
      'SELECT DISTINCT language FROM songs WHERE user_id = ? AND deleted = 0 AND trashed_at IS NULL ORDER BY language',
      variables: [Variable.withString(userId)],
    ).get();
    return result.map((row) => row.read<String>('language')).toList();
  }

  // getUniqueSongTags removed — song tags now come from the global SyncTags
  // table via the SyncSongTags junction table.

  /// Get unique scales/keys for a user
  Future<List<String>> getUniqueScales(String userId) async {
    final result = await _db.customSelect(
      "SELECT DISTINCT scale FROM songs WHERE user_id = ? AND deleted = 0 AND trashed_at IS NULL AND scale != '' ORDER BY scale",
      variables: [Variable.withString(userId)],
    ).get();
    return result.map((row) => row.read<String>('scale')).toList();
  }

  /// Get song count for a user
  Future<int> getSongCount(String userId) async {
    final result = await _db.customSelect(
      'SELECT COUNT(*) as count FROM songs WHERE user_id = ? AND deleted = 0 AND trashed_at IS NULL',
      variables: [Variable.withString(userId)],
    ).getSingle();
    return result.read<int>('count');
  }

  // ==================== WRITE OPERATIONS ====================

  /// Create a new song
  Future<SongModel> createSong({
    required String userId,
    required String title,
    String? folderId,
    String lyrics = '',
    String chords = '',
    String scale = '',
    List<ChordLine> chordLines = const [],
    String language = 'English',
    String? book,
    String tags = '',
    String notes = '',
  }) async {
    final song = SongModel.create(
      id: generateId(),
      userId: userId,
      title: title,
      folderId: folderId,
      lyrics: lyrics,
      chords: chords,
      scale: scale,
      chordLines: chordLines,
      language: language,
      book: book,
      tags: tags,
      notes: notes,
    );

    final oplogEntry = createInsertOp(song);

    await _db.transaction(() async {
      await _db.into(_db.songs).insert(_toCompanion(song));
      await _db.into(_db.oplog).insert(_oplogToCompanion(oplogEntry));
    });

    return song;
  }

  /// Update a song.
  /// Pass [clearBook] = true to explicitly set book to null.
  Future<SongModel> updateSong({
    required String id,
    String? title,
    String? folderId,
    bool clearFolderId = false,
    String? lyrics,
    String? chords,
    String? scale,
    List<ChordLine>? chordLines,
    String? language,
    String? book,
    bool clearBook = false,
    String? tags,
    String? notes,
  }) async {
    final existing = await getSongById(id);
    if (existing == null) {
      throw SongNotFoundException(id);
    }

    final updated = existing.copyWithUpdate(
      title: title,
      folderId: folderId,
      clearFolderId: clearFolderId,
      lyrics: lyrics,
      chords: chords,
      scale: scale,
      chordLines: chordLines,
      language: language,
      book: book,
      clearBook: clearBook,
      tags: tags,
      notes: notes,
    );

    final oplogEntry = createUpdateOp(updated);

    await _db.transaction(() async {
      await (_db.update(_db.songs)..where((s) => s.id.equals(id)))
          .write(_toCompanion(updated));
      await _db.into(_db.oplog).insert(_oplogToCompanion(oplogEntry));
    });

    return updated;
  }

  /// Toggle favorite status
  Future<SongModel> toggleFavorite(String id) async {
    final existing = await getSongById(id);
    if (existing == null) {
      throw SongNotFoundException(id);
    }

    final updated = existing.toggleFavorite();
    final oplogEntry = createUpdateOp(updated);

    await _db.transaction(() async {
      await (_db.update(_db.songs)..where((s) => s.id.equals(id)))
          .write(_toCompanion(updated));
      await _db.into(_db.oplog).insert(_oplogToCompanion(oplogEntry));
    });

    return updated;
  }

  /// Duplicate an existing song with a new ID/title.
  Future<SongModel> duplicateSong(
    String id, {
    String? newTitle,
    String? targetFolderId,
  }) async {
    final existing = await getSongById(id);
    if (existing == null) {
      throw SongNotFoundException(id);
    }

    return createSong(
      userId: existing.userId,
      title: newTitle ?? '${existing.title} (Copy)',
      folderId: targetFolderId ?? existing.folderId,
      lyrics: existing.lyrics,
      chords: existing.chords,
      scale: existing.scale,
      chordLines: existing.chordLinesList,
      language: existing.language,
      book: existing.book,
      tags: existing.tags,
      notes: existing.notes,
    );
  }

  /// Move song to folder
  Future<SongModel> moveSong(String id, String? targetFolderId) async {
    final existing = await getSongById(id);
    if (existing == null) {
      throw SongNotFoundException(id);
    }

    final updated = targetFolderId == null
        ? existing.copyWithUpdate(clearFolderId: true)
        : existing.copyWithUpdate(folderId: targetFolderId);
    final oplogEntry = createUpdateOp(updated);

    await _db.transaction(() async {
      await (_db.update(_db.songs)..where((s) => s.id.equals(id)))
          .write(_toCompanion(updated));
      await _db.into(_db.oplog).insert(_oplogToCompanion(oplogEntry));
    });

    return updated;
  }

  /// Move a song to the trash
  Future<SongModel> trashSong(String id) async {
    final existing = await getSongById(id);
    if (existing == null) throw SongNotFoundException(id);
    final trashed = existing.moveToTrash();
    final oplogEntry = createUpdateOp(trashed);
    await _db.transaction(() async {
      await (_db.update(_db.songs)..where((s) => s.id.equals(id)))
          .write(_toCompanion(trashed));
      await _db.into(_db.oplog).insert(_oplogToCompanion(oplogEntry));
    });
    return trashed;
  }

  /// Restore a song from the trash
  Future<SongModel> restoreSong(String id) async {
    final existing = await getSongById(id);
    if (existing == null) throw SongNotFoundException(id);
    final restored = existing.restoreFromTrash();
    final oplogEntry = createUpdateOp(restored);
    await _db.transaction(() async {
      await (_db.update(_db.songs)..where((s) => s.id.equals(id)))
          .write(_toCompanion(restored));
      await _db.into(_db.oplog).insert(_oplogToCompanion(oplogEntry));
    });
    return restored;
  }

  /// Get all trashed songs for a user
  Future<List<SongModel>> getTrashedSongs(String userId) async {
    final query = _db.select(_db.songs)
      ..where((s) => s.userId.equals(userId) & s.deleted.equals(0) & s.trashedAt.isNotNull())
      ..orderBy([(s) => OrderingTerm.desc(s.trashedAt)]);
    final rows = await query.get();
    return rows.map(_toModel).toList();
  }

  /// Watch all trashed songs for a user
  Stream<List<SongModel>> watchTrashedSongs(String userId) {
    final query = _db.select(_db.songs)
      ..where((s) => s.userId.equals(userId) & s.deleted.equals(0) & s.trashedAt.isNotNull())
      ..orderBy([(s) => OrderingTerm.desc(s.trashedAt)]);
    return query.watch().map((rows) => rows.map(_toModel).toList());
  }

  /// Soft delete a song
  Future<void> deleteSong(String id) async {
    final existing = await getSongById(id);
    if (existing == null) {
      throw SongNotFoundException(id);
    }

    final deletedSong = existing.softDelete();
    final oplogEntry = createDeleteOp(deletedSong);

    await _db.transaction(() async {
      await (_db.update(_db.songs)..where((s) => s.id.equals(id)))
          .write(_toCompanion(deletedSong));
      await _db.into(_db.oplog).insert(_oplogToCompanion(oplogEntry));
    });

    // Cascade: revoke entity_access grants for this song so recipients'
    // local DBs drop their stale access rows on next sync.
    await _entityAccessRepo.deleteAllAccessForEntity('song', id);
  }

  // ==================== SEARCH HELPERS ====================

  /// Escape SQL LIKE wildcard characters in user input.
  static String _escapeLikePattern(String input) {
    return input
        .replaceAll('\\', '\\\\')
        .replaceAll('%', '\\%')
        .replaceAll('_', '\\_');
  }

  // ==================== HELPER METHODS ====================

  /// Convert database row to domain model
  SongModel _toModel(Song row) {
    return SongModel(
      id: row.id,
      userId: row.userId,
      title: row.title,
      folderId: row.folderId,
      lyrics: row.lyrics,
      chords: row.chords,
      scale: row.scale,
      chordLinesJson: row.chordLines,
      language: row.language,
      book: row.book,
      preview: row.preview,
      tags: row.tags,
      notes: row.notes,
      hasChords: row.hasChords == 1,
      isFavorite: row.isFavorite == 1,
      updatedAt: row.updatedAt,
      version: row.version,
      deleted: row.deleted,
      trashedAt: row.trashedAt,
      createdAt: row.createdAt,
    );
  }

  /// Convert domain model to database companion
  SongsCompanion _toCompanion(SongModel model) {
    return SongsCompanion(
      id: Value(model.id),
      userId: Value(model.userId),
      title: Value(model.title),
      folderId: Value(model.folderId),
      lyrics: Value(model.lyrics),
      chords: Value(model.chords),
      scale: Value(model.scale),
      chordLines: Value(model.chordLinesJson),
      language: Value(model.language),
      book: Value(model.book),
      preview: Value(model.preview),
      tags: Value(model.tags),
      notes: Value(model.notes),
      hasChords: Value(model.hasChords ? 1 : 0),
      isFavorite: Value(model.isFavorite ? 1 : 0),
      updatedAt: Value(model.updatedAt),
      version: Value(model.version),
      deleted: Value(model.deleted),
      trashedAt: Value(model.trashedAt),
      createdAt: Value(model.createdAt),
    );
  }

  /// Convert oplog entry to database companion
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

// ==================== EXCEPTIONS ====================

class SongNotFoundException implements Exception {
  final String songId;
  SongNotFoundException(this.songId);

  @override
  String toString() => 'Song not found: $songId';
}
