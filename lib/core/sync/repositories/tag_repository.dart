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

  /// A tag's canonical name.
  ///
  /// Tags are lowercase, so "Faith" and "faith" are one tag rather than two.
  /// Normalising on write is only half of it — the lookup has to be
  /// case-insensitive too, or a tag stored as "Faith" before this rule existed
  /// would be missed and a second one created beside it.
  static String normaliseName(String name) => name.trim().toLowerCase();

  Future<TagModel?> getTagByName(String name, String userId) async {
    // LOWER() on both sides rather than an equality on the stored value: rows
    // written before tags were normalised still carry their original case.
    final rows = await _db.customSelect(
      'SELECT * FROM sync_tags '
      'WHERE LOWER(name) = ? AND user_id = ? AND deleted = 0 '
      'AND trashed_at IS NULL '
      // Oldest first, so a collision resolves to the same tag every time
      // rather than to whichever row the database happened to return.
      'ORDER BY created_at ASC, id ASC LIMIT 1',
      variables: [
        Variable.withString(normaliseName(name)),
        Variable.withString(userId),
      ],
      readsFrom: {_db.syncTags},
    ).getSingleOrNull();

    if (rows == null) return null;
    return TagModel(
      id: rows.read<String>('id'),
      userId: rows.read<String>('user_id'),
      name: rows.read<String>('name'),
      updatedAt: rows.read<int>('updated_at'),
      version: rows.read<int>('version'),
      deleted: rows.read<int>('deleted'),
      trashedAt: rows.read<int?>('trashed_at'),
      createdAt: rows.read<int>('created_at'),
    );
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
    final trimmedName = normaliseName(name);
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

    final trimmed = normaliseName(newName);
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

  /// Every junction table that points at [SyncTags], with the column naming
  /// the thing being tagged.
  ///
  /// A merge used to walk only notes and songs, so prayer and promise rows
  /// kept pointing at a tag that had just been soft-deleted — they resolved to
  /// nothing and the tag silently fell off those items. Listing the tables in
  /// one place is what stops the next junction table being forgotten too.
  /// (table, owner column, the key that column has in the model's JSON, and
  /// the oplog type the relation syncs under).
  static const _tagJunctions =
      <(String, String, String, OplogEntityType)>[
    ('sync_note_tags', 'note_id', 'noteId', OplogEntityType.noteTag),
    ('sync_song_tags', 'song_id', 'songId', OplogEntityType.songTag),
    ('sync_prayer_tags', 'prayer_id', 'prayerId', OplogEntityType.prayerTag),
    (
      'sync_promise_tags',
      'promise_id',
      'promiseId',
      OplogEntityType.promiseTag
    ),
  ];

  /// Merge [sourceTagId] into [targetTagId] across every junction table, then
  /// soft-delete the source tag.
  Future<void> mergeTags({
    required String sourceTagId,
    required String targetTagId,
  }) async {
    if (sourceTagId == targetTagId) return;

    final source = await getTagById(sourceTagId);
    final target = await getTagById(targetTagId);
    if (source == null) throw TagNotFoundException(sourceTagId);
    if (target == null) throw TagNotFoundException(targetTagId);

    await _db.transaction(() async {
      for (final (table, ownerColumn, ownerKey, type) in _tagJunctions) {
        await _repointJunction(
          table: table,
          ownerColumn: ownerColumn,
          ownerKey: ownerKey,
          entityType: type,
          sourceTagId: sourceTagId,
          targetTagId: targetTagId,
        );
      }

      final deletedTag = source.softDelete();
      final deleteOplog = createDeleteOp(deletedTag);
      await (_db.update(_db.syncTags)..where((t) => t.id.equals(sourceTagId)))
          .write(_toCompanion(deletedTag));
      await _db.into(_db.oplog).insert(_oplogToCompanion(deleteOplog));
    });
  }

  /// Moves every live row in [table] from the source tag to the target,
  /// skipping owners that already carry the target, then retires the old row.
  ///
  /// Raw SQL because the four junction tables are four unrelated Drift types
  /// with the same shape; writing this once against the shape is what keeps
  /// them from drifting apart again.
  Future<void> _repointJunction({
    required String table,
    required String ownerColumn,
    required String ownerKey,
    required OplogEntityType entityType,
    required String sourceTagId,
    required String targetTagId,
  }) async {
    final rows = await _db.customSelect(
      'SELECT id, $ownerColumn AS owner_id, user_id, version FROM $table '
      'WHERE tag_id = ? AND deleted = 0',
      variables: [Variable.withString(sourceTagId)],
    ).get();

    for (final row in rows) {
      final ownerId = row.read<String>('owner_id');
      final existing = await _db.customSelect(
        'SELECT id FROM $table '
        'WHERE $ownerColumn = ? AND tag_id = ? AND deleted = 0 LIMIT 1',
        variables: [
          Variable.withString(ownerId),
          Variable.withString(targetTagId),
        ],
      ).getSingleOrNull();

      final userId = row.read<String>('user_id');

      if (existing == null) {
        final now = TestClock.now();
        final newId = generateId();
        await _db.customStatement(
          'INSERT INTO $table '
          '(id, $ownerColumn, tag_id, user_id, updated_at, version, deleted, '
          'created_at) VALUES (?, ?, ?, ?, ?, 1, 0, ?)',
          [newId, ownerId, targetTagId, userId, now, now],
        );
        await _writeJunctionOp(
          entityType: entityType,
          operation: OplogOperation.insert,
          id: newId,
          ownerKey: ownerKey,
          ownerId: ownerId,
          tagId: targetTagId,
          userId: userId,
          timestamp: now,
          version: 1,
          deleted: 0,
        );
      }

      final retiredAt = TestClock.now();
      final retiredVersion = row.read<int>('version') + 1;
      final retiredId = row.read<String>('id');
      await _db.customStatement(
        'UPDATE $table SET deleted = 1, updated_at = ?, version = ? '
        'WHERE id = ?',
        [retiredAt, retiredVersion, retiredId],
      );
      await _writeJunctionOp(
        entityType: entityType,
        operation: OplogOperation.delete,
        id: retiredId,
        ownerKey: ownerKey,
        ownerId: ownerId,
        tagId: sourceTagId,
        userId: userId,
        timestamp: retiredAt,
        version: retiredVersion,
        deleted: 1,
      );
    }
  }

  /// Records a junction change in the oplog.
  ///
  /// Without this a merge stayed on the device it was done on: the tag's own
  /// delete synced, so other devices lost the tag and kept every relation
  /// pointing at it — the merge looked like a deletion everywhere else. The
  /// four junction models share a shape, so one payload builder covers them.
  Future<void> _writeJunctionOp({
    required OplogEntityType entityType,
    required OplogOperation operation,
    required String id,
    required String ownerKey,
    required String ownerId,
    required String tagId,
    required String userId,
    required int timestamp,
    required int version,
    required int deleted,
  }) async {
    final payload = <String, dynamic>{
      'id': id,
      ownerKey: ownerId,
      'tagId': tagId,
      'userId': userId,
      'updatedAt': timestamp,
      'version': version,
      'deleted': deleted,
      'createdAt': timestamp,
    };
    final entry = OplogEntry(
      opId: generateOpId(),
      entityType: entityType,
      entityId: id,
      operation: operation,
      payload: payload,
      timestamp: timestamp,
      deviceId: deviceId,
      entityVersion: version,
    );
    await _db.into(_db.oplog).insert(_oplogToCompanion(entry));
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
