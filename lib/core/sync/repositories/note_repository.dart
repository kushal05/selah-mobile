import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import '../../database/services/note_block_fts_service.dart';
import '../../database/sync_database.dart';
import '../models/note_block_model.dart';
import '../models/note_model.dart';
import '../models/oplog_entry.dart';
import 'base_sync_repository.dart';
import 'entity_access_repository.dart';
import '../../testing/test_clock.dart';

/// Repository for note operations (metadata only)
///
/// Per spec section 3.4:
/// - No content stored here
/// - Keeps note list fast
/// - Prevents massive row updates during typing
/// - Content is stored in NoteBlockRepository
///
/// All write operations:
/// 1. Occur in a transaction
/// 2. Update updatedAt + version
/// 3. Create an oplog entry
class NoteRepository extends BaseSyncRepository<NoteModel> {
  final SyncDatabase _db;
  final String _deviceId;
  final NoteBlockFtsService _ftsService;
  final EntityAccessRepository _entityAccessRepo;

  NoteRepository(
    this._db,
    this._deviceId,
    this._ftsService,
    this._entityAccessRepo,
  );

  @override
  String get deviceId => _deviceId;

  @override
  OplogEntityType get entityType => OplogEntityType.note;

  // ==================== READ OPERATIONS ====================

  /// Get all notes for a user (excluding deleted and trashed)
  Future<List<NoteModel>> getAllNotes(String userId) async {
    final query = _db.select(_db.syncNotes)
      ..where((n) => n.userId.equals(userId) & n.deleted.equals(0) & n.trashedAt.isNull())
      ..orderBy([(n) => OrderingTerm.desc(n.updatedAt)]);

    final rows = await query.get();
    return rows.map(_toModel).toList();
  }

  /// Get notes in a folder
  Future<List<NoteModel>> getNotesInFolder(String folderId) async {
    final query = _db.select(_db.syncNotes)
      ..where((n) => n.folderId.equals(folderId) & n.deleted.equals(0) & n.trashedAt.isNull())
      ..orderBy([(n) => OrderingTerm.desc(n.updatedAt)]);

    final rows = await query.get();
    return rows.map(_toModel).toList();
  }

  /// Get note by ID
  Future<NoteModel?> getNoteById(String id) async {
    final query = _db.select(_db.syncNotes)..where((n) => n.id.equals(id));

    final row = await query.getSingleOrNull();
    return row != null ? _toModel(row) : null;
  }

  /// Watch note by ID (reactive stream)
  Stream<NoteModel?> watchNoteById(String id) {
    final query = _db.select(_db.syncNotes)..where((n) => n.id.equals(id));

    return query.watchSingleOrNull().map((row) => row != null ? _toModel(row) : null);
  }

  /// Watch all notes for a user
  Stream<List<NoteModel>> watchAllNotes(String userId) {
    final query = _db.select(_db.syncNotes)
      ..where((n) => n.userId.equals(userId) & n.deleted.equals(0) & n.trashedAt.isNull())
      ..orderBy([(n) => OrderingTerm.desc(n.updatedAt)]);

    return query.watch().map((rows) => rows.map(_toModel).toList());
  }

  /// Watch notes in a folder
  Stream<List<NoteModel>> watchNotesInFolder(String folderId) {
    final query = _db.select(_db.syncNotes)
      ..where((n) => n.folderId.equals(folderId) & n.deleted.equals(0) & n.trashedAt.isNull())
      ..orderBy([(n) => OrderingTerm.desc(n.updatedAt)]);

    return query.watch().map((rows) => rows.map(_toModel).toList());
  }

  /// Search notes by title or content using FTS5.
  ///
  /// Searches note titles with LIKE and note block content via FTS5 MATCH.
  Future<List<NoteModel>> searchNotes(String userId, String query) async {
    final escaped = query.trim().replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_');
    final searchPattern = '%$escaped%';

    // FTS5 search for block content matches
    final ftsResults = await _ftsService.search(query, limit: 200);
    final contentMatchNoteIds = ftsResults.map((r) => r.noteId).toSet();

    // Search notes where title matches OR content matches via FTS
    final dbQuery = _db.select(_db.syncNotes)
      ..where((n) {
        final base = n.userId.equals(userId) & n.deleted.equals(0) & n.trashedAt.isNull();
        if (contentMatchNoteIds.isNotEmpty) {
          return base &
              (n.title.like(searchPattern) |
                  n.id.isIn(contentMatchNoteIds));
        }
        return base & n.title.like(searchPattern);
      })
      ..orderBy([(n) => OrderingTerm.desc(n.updatedAt)]);

    final rows = await dbQuery.get();
    return rows.map(_toModel).toList();
  }

  /// Search notes with metadata filters (tags, preacher, date range, folder)
  ///
  /// Follows the same pattern as `SongRepository.searchSongsFiltered`.
  Future<List<NoteModel>> searchNotesFiltered({
    required String userId,
    String? textQuery,
    List<String>? tagIds,
    String? preacherId,
    int? dateFrom,
    int? dateTo,
    String? folderId,
    List<String>? folderIds,
  }) async {
    final conditions = <String>["n.deleted = 0", "n.trashed_at IS NULL", "n.user_id = ?"];
    final variables = <Variable>[Variable.withString(userId)];

    if (textQuery != null && textQuery.trim().isNotEmpty) {
      final escaped = textQuery.trim().replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_');
      final pattern = '%$escaped%';

      // FTS5 search for block content matches
      final ftsResults = await _ftsService.search(textQuery, limit: 200);
      final ftsNoteIds = ftsResults.map((r) => r.noteId).toSet();

      if (ftsNoteIds.isNotEmpty) {
        final placeholders = ftsNoteIds.map((_) => '?').join(', ');
        conditions.add("(n.title LIKE ? ESCAPE '\\' OR n.id IN ($placeholders))");
        variables.add(Variable.withString(pattern));
        for (final id in ftsNoteIds) {
          variables.add(Variable.withString(id));
        }
      } else {
        conditions.add("n.title LIKE ? ESCAPE '\\'");
        variables.add(Variable.withString(pattern));
      }
    }

    if (preacherId != null && preacherId.isNotEmpty) {
      conditions.add("n.preacher_id = ?");
      variables.add(Variable.withString(preacherId));
    }

    if (dateFrom != null) {
      conditions.add("n.note_date >= ?");
      variables.add(Variable.withInt(dateFrom));
    }

    if (dateTo != null) {
      conditions.add("n.note_date <= ?");
      variables.add(Variable.withInt(dateTo));
    }

    if (folderId != null) {
      if (folderIds != null && folderIds.isNotEmpty) {
        final placeholders = folderIds.map((_) => '?').join(', ');
        conditions.add("n.folder_id IN ($placeholders)");
        for (final id in folderIds) {
          variables.add(Variable.withString(id));
        }
      } else {
        conditions.add("n.folder_id = ?");
        variables.add(Variable.withString(folderId));
      }
    }

    if (tagIds != null && tagIds.isNotEmpty) {
      final placeholders = tagIds.map((_) => '?').join(', ');
      conditions.add(
        "n.id IN (SELECT note_id FROM sync_note_tags WHERE tag_id IN ($placeholders) AND deleted = 0)",
      );
      for (final tagId in tagIds) {
        variables.add(Variable.withString(tagId));
      }
    }

    final whereClause = conditions.join(' AND ');
    final sql = 'SELECT n.* FROM sync_notes n WHERE $whereClause ORDER BY n.updated_at DESC';

    final rows = await _db.customSelect(sql, variables: variables).get();
    return rows.map((row) {
      return NoteModel(
        id: row.read<String>('id'),
        folderId: row.read<String>('folder_id'),
        userId: row.read<String>('user_id'),
        title: row.read<String>('title'),
        updatedAt: row.read<int>('updated_at'),
        version: row.read<int>('version'),
        deleted: row.read<int>('deleted'),
        trashedAt: row.readNullable<int>('trashed_at'),
        createdAt: row.read<int>('created_at'),
        preacherId: row.readNullable<String>('preacher_id'),
        noteDate: row.readNullable<int>('note_date'),
        fieldUpdatedAt: _parseFieldTimestamps(
          row.read<String>('field_updated_at'),
        ),
        documentJson: row.readNullable<String>('document_json'),
      );
    }).toList();
  }

  /// Get notes by preacher
  Future<List<NoteModel>> getNotesByPreacher(String preacherId) async {
    final query = _db.select(_db.syncNotes)
      ..where((n) => n.preacherId.equals(preacherId) & n.deleted.equals(0) & n.trashedAt.isNull())
      ..orderBy([(n) => OrderingTerm.desc(n.updatedAt)]);

    final rows = await query.get();
    return rows.map(_toModel).toList();
  }

  /// Get recently updated notes
  Future<List<NoteModel>> getRecentNotes(String userId, {int limit = 10}) async {
    final query = _db.select(_db.syncNotes)
      ..where((n) => n.userId.equals(userId) & n.deleted.equals(0) & n.trashedAt.isNull())
      ..orderBy([(n) => OrderingTerm.desc(n.updatedAt)])
      ..limit(limit);

    final rows = await query.get();
    return rows.map(_toModel).toList();
  }

  // ==================== HISTORY ====================

  /// Get the oplog history for a note, ordered newest-first.
  ///
  /// Each entry contains the full entity state at that version
  /// in [OplogEntry.payload].
  Future<List<OplogEntry>> getNoteHistory(String noteId) async {
    try {
      final query = _db.select(_db.oplog)
        ..where((o) =>
            o.entityType.equals('note') & o.entityId.equals(noteId))
        ..orderBy([(o) => OrderingTerm.desc(o.timestamp)]);

      final rows = await query.get();
      return rows.map((row) {
        return OplogEntry(
          opId: row.opId,
          entityType: OplogEntityType.fromDbValue(row.entityType),
          entityId: row.entityId,
          operation: OplogOperation.fromDbValue(row.operation),
          payload: jsonDecode(row.payloadJson) as Map<String, dynamic>,
          timestamp: row.timestamp,
          deviceId: row.deviceId,
          entityVersion: row.entityVersion,
          synced: row.synced == 1,
          serverTimestamp: row.serverTimestamp,
        );
      }).toList();
    } catch (e) {
      debugPrint('getNoteHistory($noteId) failed: $e');
      return [];
    }
  }

  // ==================== WRITE OPERATIONS ====================

  /// Create a new note
  ///
  /// Per spec: Transaction + oplog entry
  Future<NoteModel> createNote({
    String? id,
    required String folderId,
    required String userId,
    required String title,
    String? preacherId,
    int? noteDate,
  }) async {
    final note = NoteModel.create(
      id: id ?? generateId(),
      folderId: folderId,
      userId: userId,
      title: title,
      preacherId: preacherId,
      noteDate: noteDate,
    );

    final oplogEntry = createInsertOp(note);

    await _db.transaction(() async {
      await _db.into(_db.syncNotes).insert(_toCompanion(note));
      await _db.into(_db.oplog).insert(_oplogToCompanion(oplogEntry));
    });

    return note;
  }

  /// Update note metadata
  ///
  /// Per spec: Transaction + oplog entry + version increment
  Future<NoteModel> updateNote({
    required String id,
    String? folderId,
    String? title,
    String? preacherId,
    int? noteDate,
    bool clearPreacher = false,
    bool clearNoteDate = false,
  }) async {
    final existing = await getNoteById(id);
    if (existing == null) {
      throw NoteNotFoundException(id);
    }

    final updated = existing.copyWithUpdate(
      folderId: folderId,
      title: title,
      preacherId: preacherId,
      noteDate: noteDate,
      clearPreacher: clearPreacher,
      clearNoteDate: clearNoteDate,
    );

    final oplogEntry = createUpdateOp(updated);

    await _db.transaction(() async {
      await (_db.update(_db.syncNotes)..where((n) => n.id.equals(id)))
          .write(_toCompanion(updated));
      await _db.into(_db.oplog).insert(_oplogToCompanion(oplogEntry));
    });

    return updated;
  }

  /// Move note to a different folder
  Future<NoteModel> moveNote(String id, String newFolderId) async {
    return updateNote(id: id, folderId: newFolderId);
  }

  /// Move multiple notes to a different folder in a single transaction.
  ///
  /// Skips notes that are deleted or already in the target folder.
  /// Each moved note gets an updated timestamp, incremented version,
  /// and its own oplog entry.
  Future<int> moveNotes(List<String> noteIds, String targetFolderId) async {
    var movedCount = 0;

    await _db.transaction(() async {
      for (final noteId in noteIds) {
        final existing = await getNoteById(noteId);
        if (existing == null || existing.isDeleted) continue;
        if (existing.folderId == targetFolderId) continue;

        final updated = existing.copyWithUpdate(folderId: targetFolderId);
        final oplogEntry = createUpdateOp(updated);

        await (_db.update(_db.syncNotes)..where((n) => n.id.equals(noteId)))
            .write(_toCompanion(updated));
        await _db.into(_db.oplog).insert(_oplogToCompanion(oplogEntry));
        movedCount++;
      }
    });

    return movedCount;
  }

  /// Touch note (update updatedAt without other changes)
  ///
  /// Used when blocks are modified to update note's updatedAt
  Future<void> touchNote(String id) async {
    final existing = await getNoteById(id);
    if (existing == null) return;

    // Create updated note with new timestamp but same version
    // This is a metadata-only update, no oplog entry needed
    // The block changes will have their own oplog entries
    final now = TestClock.now();
    await (_db.update(_db.syncNotes)..where((n) => n.id.equals(id))).write(
      SyncNotesCompanion(updatedAt: Value(now)),
    );
  }

  /// Update the documentJson snapshot on a note.
  ///
  /// Called after block saves to keep the denormalized JSON snapshot
  /// in sync with the block table. No oplog entry — blocks have their own.
  Future<void> updateDocumentJson(String noteId, String? docJson) async {
    await (_db.update(_db.syncNotes)..where((n) => n.id.equals(noteId)))
        .write(SyncNotesCompanion(documentJson: Value(docJson)));
  }

  /// Update documentJson and touch updatedAt in a single write.
  ///
  /// This prevents the preview cache from going stale: if touchNote and
  /// updateDocumentJson are separate writes, the stream emits with the new
  /// updatedAt but the old documentJson, causing _getNotePreview to cache
  /// a stale preview under the new timestamp key.
  Future<void> updateDocumentJsonAndTouch(String noteId, String? docJson) async {
    final now = TestClock.now();
    await (_db.update(_db.syncNotes)..where((n) => n.id.equals(noteId))).write(
      SyncNotesCompanion(
        updatedAt: Value(now),
        documentJson: Value(docJson),
      ),
    );
  }

  /// Soft delete a note
  ///
  /// Per spec: Sets deleted = 1
  /// Note: Blocks are NOT automatically deleted - they remain
  /// but will be hidden since their parent note is deleted.
  /// This allows recovery of the full note with content.
  Future<void> deleteNote(String id) async {
    final existing = await getNoteById(id);
    if (existing == null) {
      throw NoteNotFoundException(id);
    }

    final deletedNote = existing.softDelete();
    final oplogEntry = createDeleteOp(deletedNote);

    await _db.transaction(() async {
      await (_db.update(_db.syncNotes)..where((n) => n.id.equals(id)))
          .write(_toCompanion(deletedNote));
      await _db.into(_db.oplog).insert(_oplogToCompanion(oplogEntry));
    });

    // Cascade: revoke every share for this note so local repos stop
    // surfacing stale access rows. Server does the same cascade on the
    // note DELETE op, which gives recipients their authoritative revoke.
    await _entityAccessRepo.deleteAllAccessForEntity('note', id);
  }

  /// Delete all notes in a folder (called when folder is deleted)
  Future<void> deleteNotesInFolder(String folderId) async {
    final notes = await getNotesInFolder(folderId);

    await _db.transaction(() async {
      for (final note in notes) {
        final deletedNote = note.softDelete();
        final oplogEntry = createDeleteOp(deletedNote);

        await (_db.update(_db.syncNotes)..where((n) => n.id.equals(note.id)))
            .write(_toCompanion(deletedNote));
        await _db.into(_db.oplog).insert(_oplogToCompanion(oplogEntry));
      }
    });

    // Cascade: revoke entity_access grants for each deleted note.
    // Runs after the transaction so the access-row deletes emit their own
    // oplog entries without nesting transactions.
    for (final note in notes) {
      await _entityAccessRepo.deleteAllAccessForEntity('note', note.id);
    }
  }

  // ==================== TRASH OPERATIONS ====================

  /// Move note to trash
  Future<NoteModel> trashNote(String id) async {
    final existing = await getNoteById(id);
    if (existing == null) throw NoteNotFoundException(id);

    final trashed = existing.moveToTrash();
    final oplogEntry = createUpdateOp(trashed);

    await _db.transaction(() async {
      await (_db.update(_db.syncNotes)..where((n) => n.id.equals(id)))
          .write(_toCompanion(trashed));
      await _db.into(_db.oplog).insert(_oplogToCompanion(oplogEntry));
    });

    // Cascade: trash all blocks for this note
    await _trashBlocksForNote(id);

    return trashed;
  }

  /// Restore note from trash
  Future<NoteModel> restoreNote(String id) async {
    final existing = await getNoteById(id);
    if (existing == null) throw NoteNotFoundException(id);

    final restored = existing.restoreFromTrash();
    final oplogEntry = createUpdateOp(restored);

    await _db.transaction(() async {
      await (_db.update(_db.syncNotes)..where((n) => n.id.equals(id)))
          .write(_toCompanion(restored));
      await _db.into(_db.oplog).insert(_oplogToCompanion(oplogEntry));
    });

    // Cascade: restore all blocks for this note
    await _restoreBlocksForNote(id);

    return restored;
  }

  /// Get all trashed notes for a user
  Future<List<NoteModel>> getTrashedNotes(String userId) async {
    final query = _db.select(_db.syncNotes)
      ..where((n) => n.userId.equals(userId) & n.deleted.equals(0) & n.trashedAt.isNotNull())
      ..orderBy([(n) => OrderingTerm.desc(n.trashedAt)]);
    final rows = await query.get();
    return rows.map(_toModel).toList();
  }

  /// Watch trashed notes for a user
  Stream<List<NoteModel>> watchTrashedNotes(String userId) {
    final query = _db.select(_db.syncNotes)
      ..where((n) => n.userId.equals(userId) & n.deleted.equals(0) & n.trashedAt.isNotNull())
      ..orderBy([(n) => OrderingTerm.desc(n.trashedAt)]);
    return query.watch().map((rows) => rows.map(_toModel).toList());
  }

  /// Trash all non-trashed blocks for a note
  Future<void> _trashBlocksForNote(String noteId) async {
    final query = _db.select(_db.noteBlocks)
      ..where((b) => b.noteId.equals(noteId) & b.deleted.equals(0) & b.trashedAt.isNull());
    final rows = await query.get();

    await _db.transaction(() async {
      for (final row in rows) {
        final block = NoteBlockModel(
          id: row.id,
          noteId: row.noteId,
          blockType: BlockType.fromDbValue(row.blockType),
          content: _parseContentJson(row.contentJson),
          orderIndex: row.orderIndex,
          updatedAt: row.updatedAt,
          version: row.version,
          deleted: row.deleted,
          createdAt: row.createdAt,
          section: row.section,
        );
        final trashedBlock = block.moveToTrash();
        final oplogEntry = createBlockUpdateOp(trashedBlock);

        await (_db.update(_db.noteBlocks)..where((b) => b.id.equals(block.id)))
            .write(_toBlockCompanion(trashedBlock));
        await _db.into(_db.oplog).insert(_oplogToCompanion(oplogEntry));
      }
    });
  }

  /// Restore all trashed blocks for a note
  Future<void> _restoreBlocksForNote(String noteId) async {
    final query = _db.select(_db.noteBlocks)
      ..where((b) => b.noteId.equals(noteId) & b.deleted.equals(0) & b.trashedAt.isNotNull());
    final rows = await query.get();

    await _db.transaction(() async {
      for (final row in rows) {
        final block = NoteBlockModel(
          id: row.id,
          noteId: row.noteId,
          blockType: BlockType.fromDbValue(row.blockType),
          content: _parseContentJson(row.contentJson),
          orderIndex: row.orderIndex,
          updatedAt: row.updatedAt,
          version: row.version,
          deleted: row.deleted,
          createdAt: row.createdAt,
          section: row.section,
        );
        final restoredBlock = block.restoreFromTrash();
        final oplogEntry = createBlockUpdateOp(restoredBlock);

        await (_db.update(_db.noteBlocks)..where((b) => b.id.equals(block.id)))
            .write(_toBlockCompanion(restoredBlock));
        await _db.into(_db.oplog).insert(_oplogToCompanion(oplogEntry));
      }
    });
  }

  /// Create an UPDATE oplog entry for a note block
  OplogEntry createBlockUpdateOp(NoteBlockModel block) {
    return OplogEntry(
      opId: generateId(),
      entityType: OplogEntityType.noteBlock,
      entityId: block.id,
      operation: OplogOperation.update,
      payload: block.toJson(),
      timestamp: block.updatedAt,
      deviceId: deviceId,
      entityVersion: block.version,
    );
  }

  /// Convert NoteBlockModel to database companion (for cascade operations)
  NoteBlocksCompanion _toBlockCompanion(NoteBlockModel model) {
    return NoteBlocksCompanion(
      id: Value(model.id),
      noteId: Value(model.noteId),
      blockType: Value(model.blockType.toDbValue()),
      contentJson: Value(jsonEncode(model.content)),
      orderIndex: Value(model.orderIndex),
      updatedAt: Value(model.updatedAt),
      version: Value(model.version),
      deleted: Value(model.deleted),
      trashedAt: Value(model.trashedAt),
      createdAt: Value(model.createdAt),
      section: Value(model.section),
    );
  }

  static Map<String, dynamic> _parseContentJson(String raw) {
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  // ==================== HELPER METHODS ====================

  /// Convert database row to domain model
  NoteModel _toModel(SyncNote row) {
    return NoteModel(
      id: row.id,
      folderId: row.folderId,
      userId: row.userId,
      title: row.title,
      updatedAt: row.updatedAt,
      version: row.version,
      deleted: row.deleted,
      createdAt: row.createdAt,
      trashedAt: row.trashedAt,
      preacherId: row.preacherId,
      noteDate: row.noteDate,
      fieldUpdatedAt: _parseFieldTimestamps(row.fieldUpdatedAt),
      documentJson: row.documentJson,
    );
  }

  /// Convert domain model to database companion
  SyncNotesCompanion _toCompanion(NoteModel model) {
    return SyncNotesCompanion(
      id: Value(model.id),
      folderId: Value(model.folderId),
      userId: Value(model.userId),
      title: Value(model.title),
      updatedAt: Value(model.updatedAt),
      version: Value(model.version),
      deleted: Value(model.deleted),
      trashedAt: Value(model.trashedAt),
      createdAt: Value(model.createdAt),
      preacherId: Value(model.preacherId),
      noteDate: Value(model.noteDate),
      fieldUpdatedAt: Value(jsonEncode(model.fieldUpdatedAt)),
      documentJson: Value(model.documentJson),
    );
  }

  static Map<String, int> _parseFieldTimestamps(String raw) {
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map((k, v) => MapEntry(k, (v as num).toInt()));
    } catch (_) {
      return {};
    }
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

class NoteNotFoundException implements Exception {
  final String noteId;
  NoteNotFoundException(this.noteId);

  @override
  String toString() => 'Note not found: $noteId';
}
