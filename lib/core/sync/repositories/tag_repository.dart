import 'package:drift/drift.dart';

import '../../database/services/note_block_fts_service.dart';
import '../../database/sync_database.dart';
import '../../../features/notes/domain/services/inline_tag_parser.dart';
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

  /// Throws [TagStillWrittenException] while any note's text still contains
  /// `#name`: a note derives its tags from its text on every save, so the
  /// next save would only bring the tag back.
  Future<void> deleteTag(String id) async {
    final existing = await getTagById(id);
    if (existing == null) return;

    final writers = await countNotesWritingTag(existing.name, existing.userId);
    if (writers > 0) {
      throw TagStillWrittenException(existing.name, writers);
    }
    await _softDeleteTag(existing);
  }

  /// [deleteTag] for many tags, reading the notes once instead of once per
  /// tag — what Empty Trash and the Trash purge need. Tags still written as
  /// `#name` are kept, not thrown for, and returned so the caller can say so.
  ///
  /// The notes are read up front, so a caller that also deletes notes (Empty
  /// Trash, the purge) must do that first, as both already do.
  Future<({int deleted, List<TagStillWrittenException> kept})> deleteTags(
    List<String> ids,
  ) async {
    final writtenByUser = <String, Map<String, int>>{};
    final kept = <TagStillWrittenException>[];
    var deleted = 0;
    for (final id in ids) {
      final tag = await getTagById(id);
      if (tag == null) continue;
      final written = writtenByUser[tag.userId] ??=
          await countNotesWritingTags(tag.userId);
      final writers = written[tag.name.trim().toLowerCase()] ?? 0;
      if (writers > 0) {
        kept.add(TagStillWrittenException(tag.name, writers));
        continue;
      }
      await _softDeleteTag(tag);
      deleted++;
    }
    return (deleted: deleted, kept: kept);
  }

  Future<void> _softDeleteTag(TagModel existing) async {
    final deleted = existing.softDelete();
    final oplogEntry = createDeleteOp(deleted);

    await _db.transaction(() async {
      await (_db.update(_db.syncTags)..where((t) => t.id.equals(existing.id)))
          .write(_toCompanion(deleted));
      await _db.into(_db.oplog).insert(_oplogToCompanion(oplogEntry));
      // Its links on notes, songs, prayers and promises go with it. Trash
      // keeps them, so a restored tag is back on everything it was on; only
      // this is final.
      await _retireJunctionRowsForTag(existing.id);
    });
  }

  /// How many of the user's notes write [name] as `#name` in their text.
  ///
  /// Read the way the note editor derives tags: every block's plain text
  /// except Bible references, parsed by the same [InlineTagParser], so this
  /// agrees with what the next save would put back. Notes in Trash or
  /// deleted do not count; the user cannot see them to edit them.
  ///
  /// Known consequence, accepted: restore a trashed note that writes `#name`
  /// after the tag was deleted, and its next save creates the tag again.
  /// Counting trashed notes was the alternative and was rejected — refusing a
  /// delete over something only reachable through Trash is more confusing,
  /// and restoring a note is a deliberate act.
  Future<int> countNotesWritingTag(String name, String userId) async =>
      (await countNotesWritingTags(userId))[name.trim().toLowerCase()] ?? 0;

  /// Every name the user's notes write as `#name`, with how many notes write
  /// it, in one pass over the notes. Read as [countNotesWritingTag] describes.
  Future<Map<String, int>> countNotesWritingTags(String userId) async {
    final rows = await _db.customSelect(
      'SELECT b.note_id, b.content_json FROM note_blocks b '
      'JOIN sync_notes n ON n.id = b.note_id '
      'WHERE n.user_id = ? AND n.deleted = 0 AND n.trashed_at IS NULL '
      'AND b.deleted = 0 AND b.trashed_at IS NULL '
      "AND b.block_type != 'bibleReference' "
      // A cheap filter only. Matching is left to the parser, which knows
      // the word boundaries and the case folding.
      "AND b.content_json LIKE '%#%'",
      variables: [Variable.withString(userId)],
      readsFrom: {_db.noteBlocks, _db.syncNotes},
    ).get();

    final notesByName = <String, Set<String>>{};
    for (final row in rows) {
      final text =
          NoteBlockFtsService.extractPlainText(row.read<String>('content_json'));
      final noteId = row.read<String>('note_id');
      for (final name in InlineTagParser.names(text)) {
        (notesByName[name] ??= <String>{}).add(noteId);
      }
    }
    return {
      for (final entry in notesByName.entries) entry.key: entry.value.length,
    };
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
  ///
  /// Throws [TagStillWrittenException] while notes still write the source as
  /// `#name`, for the same reason as [deleteTag]: the next save of those notes
  /// would bring it back. The text is the user's, so it is not rewritten.
  Future<void> mergeTags({
    required String sourceTagId,
    required String targetTagId,
  }) async {
    if (sourceTagId == targetTagId) return;

    final source = await getTagById(sourceTagId);
    final target = await getTagById(targetTagId);
    if (source == null) throw TagNotFoundException(sourceTagId);
    if (target == null) throw TagNotFoundException(targetTagId);

    final writers = await countNotesWritingTag(source.name, source.userId);
    if (writers > 0) {
      throw TagStillWrittenException(source.name, writers);
    }

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
      'SELECT id, $ownerColumn AS owner_id, user_id, version, created_at '
      'FROM $table WHERE tag_id = ? AND deleted = 0',
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
          createdAt: now,
        );
      }

      await _retireJunctionRow(
        table: table,
        ownerKey: ownerKey,
        entityType: entityType,
        tagId: sourceTagId,
        row: row,
      );
    }
  }

  /// Retires every live row in every junction table that points at [tagId].
  ///
  /// Used when a tag is deleted for good. Left live, the rows pointed at a
  /// tag that no longer exists: invisible in the app, which resolves names
  /// against live tags, but enough to stop the server's GC from ever
  /// hard-deleting the tag, since it skips parents with live children.
  Future<void> _retireJunctionRowsForTag(String tagId) async {
    for (final (table, ownerColumn, ownerKey, type) in _tagJunctions) {
      final rows = await _db.customSelect(
        'SELECT id, $ownerColumn AS owner_id, user_id, version, created_at '
        'FROM $table WHERE tag_id = ? AND deleted = 0',
        variables: [Variable.withString(tagId)],
      ).get();
      for (final row in rows) {
        await _retireJunctionRow(
          table: table,
          ownerKey: ownerKey,
          entityType: type,
          tagId: tagId,
          row: row,
        );
      }
    }
  }

  /// Soft-deletes one junction [row] (selected with id, owner_id, user_id,
  /// version and created_at) and records it in the oplog. Shared by merge
  /// and delete so the two cannot write different payloads.
  Future<void> _retireJunctionRow({
    required String table,
    required String ownerKey,
    required OplogEntityType entityType,
    required String tagId,
    required QueryRow row,
  }) async {
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
      ownerId: row.read<String>('owner_id'),
      tagId: tagId,
      userId: row.read<String>('user_id'),
      timestamp: retiredAt,
      version: retiredVersion,
      deleted: 1,
      createdAt: row.read<int>('created_at'),
    );
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
    required int createdAt,
  }) async {
    final payload = <String, dynamic>{
      'id': id,
      ownerKey: ownerId,
      'tagId': tagId,
      'userId': userId,
      'updatedAt': timestamp,
      'version': version,
      'deleted': deleted,
      // The row's own creation time. It was sent as [timestamp], so every
      // merge rewrote the link's creation date on the server to the moment
      // it was retired.
      'createdAt': createdAt,
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

/// A tag that notes still write as `#name`, so deleting it would not stick.
class TagStillWrittenException implements Exception {
  final String name;
  final int noteCount;
  const TagStillWrittenException(this.name, this.noteCount);

  @override
  String toString() =>
      'Tag "$name" is still written as #$name in $noteCount note(s)';
}

class TagValidationException implements Exception {
  final String message;
  const TagValidationException(this.message);

  @override
  String toString() => message;
}
