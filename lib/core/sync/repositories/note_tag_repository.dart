import 'package:drift/drift.dart';

import '../../database/sync_database.dart';
import '../models/note_tag_model.dart';
import '../models/oplog_entry.dart';
import 'base_sync_repository.dart';

/// Repository for note-tag junction operations (sync-enabled)
class NoteTagRepository extends BaseSyncRepository<NoteTagModel> {
  final SyncDatabase _db;
  final String _deviceId;

  NoteTagRepository(this._db, this._deviceId);

  @override
  String get deviceId => _deviceId;

  @override
  OplogEntityType get entityType => OplogEntityType.noteTag;

  // ==================== READ OPERATIONS ====================

  /// Get all tag IDs for a note
  Future<List<String>> getTagIdsForNote(String noteId) async {
    final query = _db.select(_db.syncNoteTags)
      ..where((nt) => nt.noteId.equals(noteId) & nt.deleted.equals(0) & nt.trashedAt.isNull());

    final rows = await query.get();
    return rows.map((r) => r.tagId).toList();
  }

  /// Get all note-tag associations for a note
  Future<List<NoteTagModel>> getTagsForNote(String noteId) async {
    final query = _db.select(_db.syncNoteTags)
      ..where((nt) => nt.noteId.equals(noteId) & nt.deleted.equals(0) & nt.trashedAt.isNull());

    final rows = await query.get();
    return rows.map(_toModel).toList();
  }

  /// Watch tag IDs for a note (reactive)
  Stream<List<String>> watchTagIdsForNote(String noteId) {
    final query = _db.select(_db.syncNoteTags)
      ..where((nt) => nt.noteId.equals(noteId) & nt.deleted.equals(0) & nt.trashedAt.isNull());

    return query.watch().map((rows) => rows.map((r) => r.tagId).toList());
  }

  /// Get all note IDs that have a specific tag
  Future<List<String>> getNoteIdsWithTag(String tagId) async {
    final query = _db.select(_db.syncNoteTags)
      ..where((nt) => nt.tagId.equals(tagId) & nt.deleted.equals(0) & nt.trashedAt.isNull());

    final rows = await query.get();
    return rows.map((r) => r.noteId).toList();
  }

  // ==================== WRITE OPERATIONS ====================

  Future<NoteTagModel> addTagToNote({
    required String noteId,
    required String tagId,
    required String userId,
  }) async {
    // Check for existing (including soft-deleted) to prevent duplicates
    final existing = await (_db.select(_db.syncNoteTags)
          ..where((nt) =>
              nt.noteId.equals(noteId) & nt.tagId.equals(tagId)))
        .getSingleOrNull();

    if (existing != null && existing.deleted == 0) {
      return _toModel(existing);
    }

    final noteTag = NoteTagModel.create(
      id: existing?.id ?? generateId(),
      noteId: noteId,
      tagId: tagId,
      userId: userId,
    );

    final oplogEntry = createInsertOp(noteTag);

    await _db.transaction(() async {
      await _db.into(_db.syncNoteTags).insertOnConflictUpdate(_toCompanion(noteTag));
      await _db.into(_db.oplog).insert(_oplogToCompanion(oplogEntry));
    });

    return noteTag;
  }

  Future<void> removeTagFromNote(String noteId, String tagId) async {
    final query = _db.select(_db.syncNoteTags)
      ..where((nt) =>
          nt.noteId.equals(noteId) &
          nt.tagId.equals(tagId) &
          nt.deleted.equals(0));

    final row = await query.getSingleOrNull();
    if (row == null) return;

    final model = _toModel(row);
    final deleted = model.softDelete();
    final oplogEntry = createDeleteOp(deleted);

    await _db.transaction(() async {
      await (_db.update(_db.syncNoteTags)..where((nt) => nt.id.equals(model.id)))
          .write(_toCompanion(deleted));
      await _db.into(_db.oplog).insert(_oplogToCompanion(oplogEntry));
    });
  }

  /// Replace all tags for a note with the given set.
  /// Diffs existing vs desired to minimize oplog entries.
  Future<void> setTagsForNote(
    String noteId,
    List<String> tagIds,
    String userId,
  ) async {
    final current = await getTagsForNote(noteId);
    final currentTagIds = current.map((nt) => nt.tagId).toSet();
    final desiredTagIds = tagIds.toSet();

    // Tags to add
    final toAdd = desiredTagIds.difference(currentTagIds);
    // Tags to remove
    final toRemove = currentTagIds.difference(desiredTagIds);

    for (final tagId in toAdd) {
      await addTagToNote(noteId: noteId, tagId: tagId, userId: userId);
    }
    for (final tagId in toRemove) {
      await removeTagFromNote(noteId, tagId);
    }
  }

  // ==================== HELPERS ====================

  NoteTagModel _toModel(SyncNoteTag row) {
    return NoteTagModel(
      id: row.id,
      noteId: row.noteId,
      tagId: row.tagId,
      userId: row.userId,
      updatedAt: row.updatedAt,
      version: row.version,
      deleted: row.deleted,
      trashedAt: row.trashedAt,
      createdAt: row.createdAt,
    );
  }

  SyncNoteTagsCompanion _toCompanion(NoteTagModel model) {
    return SyncNoteTagsCompanion(
      id: Value(model.id),
      noteId: Value(model.noteId),
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
