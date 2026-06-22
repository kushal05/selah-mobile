import 'package:drift/drift.dart';

import '../../database/sync_database.dart';
import '../models/oplog_entry.dart';
import '../models/tag_model.dart';
import 'base_sync_repository.dart';
import '../../testing/test_clock.dart';

/// Repository for tag operations (sync-enabled)
class TagRepository extends BaseSyncRepository<TagModel> {
  final SyncDatabase _db;
  final String _deviceId;

  TagRepository(this._db, this._deviceId);

  @override
  String get deviceId => _deviceId;

  @override
  OplogEntityType get entityType => OplogEntityType.tag;

  // ==================== READ OPERATIONS ====================

  Future<List<TagModel>> getAllTags(String userId) async {
    final query = _db.select(_db.syncTags)
      ..where((t) => t.userId.equals(userId) & t.deleted.equals(0) & t.trashedAt.isNull())
      ..orderBy([(t) => OrderingTerm.asc(t.name)]);

    final rows = await query.get();
    return rows.map(_toModel).toList();
  }

  Future<TagModel?> getTagById(String id) async {
    final query = _db.select(_db.syncTags)..where((t) => t.id.equals(id));

    final row = await query.getSingleOrNull();
    return row != null ? _toModel(row) : null;
  }

  Future<TagModel?> getTagByName(String name, String userId) async {
    final query = _db.select(_db.syncTags)
      ..where(
          (t) => t.name.equals(name) & t.userId.equals(userId) & t.deleted.equals(0) & t.trashedAt.isNull());

    final row = await query.getSingleOrNull();
    return row != null ? _toModel(row) : null;
  }

  Stream<List<TagModel>> watchAllTags(String userId) {
    final query = _db.select(_db.syncTags)
      ..where((t) => t.userId.equals(userId) & t.deleted.equals(0) & t.trashedAt.isNull())
      ..orderBy([(t) => OrderingTerm.asc(t.name)]);

    return query.watch().map((rows) => rows.map(_toModel).toList());
  }

  /// Get usage counts for all tags: how many notes + songs use each tag.
  ///
  /// Returns a map of tagId → count.
  Future<Map<String, int>> getTagUsageCounts(String userId) async {
    final results = await _db.customSelect(
      '''
      SELECT t.id AS tag_id,
        (SELECT COUNT(*) FROM sync_note_tags nt
         WHERE nt.tag_id = t.id AND nt.deleted = 0) +
        (SELECT COUNT(*) FROM sync_song_tags st
         WHERE st.tag_id = t.id AND st.deleted = 0) +
        (SELECT COUNT(*) FROM sync_prayer_tags pt
         WHERE pt.tag_id = t.id AND pt.deleted = 0) +
        (SELECT COUNT(*) FROM sync_promise_tags prt
         WHERE prt.tag_id = t.id AND prt.deleted = 0)
        AS usage_count
      FROM sync_tags t
      WHERE t.user_id = ? AND t.deleted = 0 AND t.trashed_at IS NULL
      ''',
      variables: [Variable.withString(userId)],
    ).get();

    final counts = <String, int>{};
    for (final row in results) {
      counts[row.read<String>('tag_id')] = row.read<int>('usage_count');
    }
    return counts;
  }

  // ==================== WRITE OPERATIONS ====================

  Future<TagModel> createTag({
    required String userId,
    required String name,
  }) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw const TagValidationException('Tag name cannot be empty');
    }

    final tag = TagModel.create(
      id: generateId(),
      userId: userId,
      name: trimmedName,
    );

    final oplogEntry = createInsertOp(tag);

    await _db.transaction(() async {
      await _db.into(_db.syncTags).insert(_toCompanion(tag));
      await _db.into(_db.oplog).insert(_oplogToCompanion(oplogEntry));
    });

    return tag;
  }

  /// Get an existing tag by name, or create a new one.
  Future<TagModel> getOrCreateTag(String name, String userId) async {
    final existing = await getTagByName(name, userId);
    if (existing != null) return existing;
    return createTag(userId: userId, name: name);
  }

  /// Move a tag to the trash
  Future<TagModel> trashTag(String id) async {
    final existing = await getTagById(id);
    if (existing == null) throw TagNotFoundException(id);
    final trashed = existing.moveToTrash();
    final oplogEntry = createUpdateOp(trashed);
    await _db.transaction(() async {
      await (_db.update(_db.syncTags)..where((t) => t.id.equals(id)))
          .write(_toCompanion(trashed));
      await _db.into(_db.oplog).insert(_oplogToCompanion(oplogEntry));
    });
    return trashed;
  }

  /// Restore a tag from the trash
  Future<TagModel> restoreTag(String id) async {
    final existing = await getTagById(id);
    if (existing == null) throw TagNotFoundException(id);
    final restored = existing.restoreFromTrash();
    final oplogEntry = createUpdateOp(restored);
    await _db.transaction(() async {
      await (_db.update(_db.syncTags)..where((t) => t.id.equals(id)))
          .write(_toCompanion(restored));
      await _db.into(_db.oplog).insert(_oplogToCompanion(oplogEntry));
    });
    return restored;
  }

  /// Get all trashed tags for a user
  Future<List<TagModel>> getTrashedTags(String userId) async {
    final query = _db.select(_db.syncTags)
      ..where((t) => t.userId.equals(userId) & t.deleted.equals(0) & t.trashedAt.isNotNull())
      ..orderBy([(t) => OrderingTerm.desc(t.trashedAt)]);
    final rows = await query.get();
    return rows.map(_toModel).toList();
  }

  /// Watch all trashed tags for a user
  Stream<List<TagModel>> watchTrashedTags(String userId) {
    final query = _db.select(_db.syncTags)
      ..where((t) => t.userId.equals(userId) & t.deleted.equals(0) & t.trashedAt.isNotNull())
      ..orderBy([(t) => OrderingTerm.desc(t.trashedAt)]);
    return query.watch().map((rows) => rows.map(_toModel).toList());
  }

  Future<void> deleteTag(String id) async {
    final existing = await getTagById(id);
    if (existing == null) return;

    final deleted = existing.softDelete();
    final oplogEntry = createDeleteOp(deleted);

    await _db.transaction(() async {
      await (_db.update(_db.syncTags)..where((t) => t.id.equals(id)))
          .write(_toCompanion(deleted));
      await _db.into(_db.oplog).insert(_oplogToCompanion(oplogEntry));
    });
  }

  /// Rename a tag and keep existing relationships.
  Future<TagModel> renameTag({
    required String id,
    required String newName,
  }) async {
    final existing = await getTagById(id);
    if (existing == null) {
      throw TagNotFoundException(id);
    }

    final trimmed = newName.trim();
    if (trimmed.isEmpty) {
      throw const TagValidationException('Tag name cannot be empty');
    }

    final sameName =
        await getTagByName(trimmed, existing.userId);
    if (sameName != null && sameName.id != id) {
      throw TagValidationException('Tag "$trimmed" already exists');
    }

    final updated = TagModel(
      id: existing.id,
      userId: existing.userId,
      name: trimmed,
      updatedAt: TestClock.now(),
      version: existing.version + 1,
      deleted: existing.deleted,
      createdAt: existing.createdAt,
    );
    final oplogEntry = createUpdateOp(updated);

    await _db.transaction(() async {
      await (_db.update(_db.syncTags)..where((t) => t.id.equals(id)))
          .write(_toCompanion(updated));
      await _db.into(_db.oplog).insert(_oplogToCompanion(oplogEntry));
    });

    return updated;
  }

  /// Merge [sourceTagId] into [targetTagId] for note-tag and song-tag
  /// relations, then soft-delete the source tag.
  Future<void> mergeTags({
    required String sourceTagId,
    required String targetTagId,
  }) async {
    if (sourceTagId == targetTagId) return;

    final source = await getTagById(sourceTagId);
    final target = await getTagById(targetTagId);
    if (source == null) throw TagNotFoundException(sourceTagId);
    if (target == null) throw TagNotFoundException(targetTagId);

    final sourceNoteRelations = await (_db.select(_db.syncNoteTags)
          ..where((n) =>
              n.tagId.equals(sourceTagId) & n.deleted.equals(0)))
        .get();

    final sourceSongRelations = await (_db.select(_db.syncSongTags)
          ..where((s) =>
              s.tagId.equals(sourceTagId) & s.deleted.equals(0)))
        .get();

    await _db.transaction(() async {
      // Migrate note-tag relations
      for (final relation in sourceNoteRelations) {
        final duplicate = await (_db.select(_db.syncNoteTags)
              ..where((n) =>
                  n.noteId.equals(relation.noteId) &
                  n.tagId.equals(targetTagId) &
                  n.deleted.equals(0)))
            .getSingleOrNull();

        if (duplicate == null) {
          await _db.into(_db.syncNoteTags).insert(
                SyncNoteTagsCompanion.insert(
                  id: generateId(),
                  noteId: relation.noteId,
                  tagId: targetTagId,
                  userId: relation.userId,
                  updatedAt: TestClock.now(),
                  createdAt: TestClock.now(),
                  version: const Value(1),
                  deleted: const Value(0),
                ),
              );
        }

        final deletedRelation = SyncNoteTagsCompanion(
          deleted: const Value(1),
          updatedAt: Value(TestClock.now()),
          version: Value(relation.version + 1),
        );
        await (_db.update(_db.syncNoteTags)..where((n) => n.id.equals(relation.id)))
            .write(deletedRelation);
      }

      // Migrate song-tag relations
      for (final relation in sourceSongRelations) {
        final duplicate = await (_db.select(_db.syncSongTags)
              ..where((s) =>
                  s.songId.equals(relation.songId) &
                  s.tagId.equals(targetTagId) &
                  s.deleted.equals(0)))
            .getSingleOrNull();

        if (duplicate == null) {
          await _db.into(_db.syncSongTags).insert(
                SyncSongTagsCompanion.insert(
                  id: generateId(),
                  songId: relation.songId,
                  tagId: targetTagId,
                  userId: relation.userId,
                  updatedAt: TestClock.now(),
                  createdAt: TestClock.now(),
                  version: const Value(1),
                  deleted: const Value(0),
                ),
              );
        }

        final deletedRelation = SyncSongTagsCompanion(
          deleted: const Value(1),
          updatedAt: Value(TestClock.now()),
          version: Value(relation.version + 1),
        );
        await (_db.update(_db.syncSongTags)..where((s) => s.id.equals(relation.id)))
            .write(deletedRelation);
      }

      final deletedTag = source.softDelete();
      final deleteOplog = createDeleteOp(deletedTag);
      await (_db.update(_db.syncTags)..where((t) => t.id.equals(sourceTagId)))
          .write(_toCompanion(deletedTag));
      await _db.into(_db.oplog).insert(_oplogToCompanion(deleteOplog));
    });
  }

  // ==================== HELPERS ====================

  TagModel _toModel(SyncTag row) {
    return TagModel(
      id: row.id,
      userId: row.userId,
      name: row.name,
      updatedAt: row.updatedAt,
      version: row.version,
      deleted: row.deleted,
      trashedAt: row.trashedAt,
      createdAt: row.createdAt,
    );
  }

  SyncTagsCompanion _toCompanion(TagModel model) {
    return SyncTagsCompanion(
      id: Value(model.id),
      userId: Value(model.userId),
      name: Value(model.name),
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

class TagNotFoundException implements Exception {
  final String tagId;
  TagNotFoundException(this.tagId);

  @override
  String toString() => 'Tag not found: $tagId';
}

class TagValidationException implements Exception {
  final String message;
  const TagValidationException(this.message);

  @override
  String toString() => message;
}
