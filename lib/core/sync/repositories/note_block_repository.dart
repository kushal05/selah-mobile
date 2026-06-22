import 'dart:convert';

import 'package:drift/drift.dart';

import '../../database/services/note_block_fts_service.dart';
import '../../database/sync_database.dart';
import '../models/note_block_model.dart';
import '../models/oplog_entry.dart';
import 'base_sync_repository.dart';

/// Repository for note block operations (content layer)
///
/// Per spec section 3.5:
/// - Enables partial updates
/// - Smaller sync payloads
/// - Better conflict isolation
///
/// Block-based architecture means:
/// - Each block syncs independently
/// - Typing in one block doesn't affect others
/// - Conflict resolution happens at block level
///
/// Per spec section 7:
/// - Never auto-merge rich text blocks
class NoteBlockRepository extends BaseSyncRepository<NoteBlockModel> {
  final SyncDatabase _db;
  final String _deviceId;
  final NoteBlockFtsService _ftsService;

  NoteBlockRepository(this._db, this._deviceId, this._ftsService);

  @override
  String get deviceId => _deviceId;

  @override
  OplogEntityType get entityType => OplogEntityType.noteBlock;

  // ==================== READ OPERATIONS ====================

  /// Get all blocks for a note (ordered)
  Future<List<NoteBlockModel>> getBlocksForNote(String noteId) async {
    final query = _db.select(_db.noteBlocks)
      ..where((b) => b.noteId.equals(noteId) & b.deleted.equals(0) & b.trashedAt.isNull())
      ..orderBy([(b) => OrderingTerm.asc(b.orderIndex)]);

    final rows = await query.get();
    return rows.map(_toModel).toList();
  }

  /// Get block by ID
  Future<NoteBlockModel?> getBlockById(String id) async {
    final query = _db.select(_db.noteBlocks)..where((b) => b.id.equals(id));

    final row = await query.getSingleOrNull();
    return row != null ? _toModel(row) : null;
  }

  /// Watch blocks for a note (reactive stream)
  Stream<List<NoteBlockModel>> watchBlocksForNote(String noteId) {
    final query = _db.select(_db.noteBlocks)
      ..where((b) => b.noteId.equals(noteId) & b.deleted.equals(0) & b.trashedAt.isNull())
      ..orderBy([(b) => OrderingTerm.asc(b.orderIndex)]);

    return query.watch().map((rows) => rows.map(_toModel).toList());
  }

  /// Watch a single block
  Stream<NoteBlockModel?> watchBlockById(String id) {
    final query = _db.select(_db.noteBlocks)..where((b) => b.id.equals(id));

    return query.watchSingleOrNull().map((row) => row != null ? _toModel(row) : null);
  }

  /// Get block count for a note
  Future<int> getBlockCount(String noteId) async {
    final result = await _db.customSelect(
      'SELECT COUNT(*) as count FROM note_blocks WHERE note_id = ? AND deleted = 0 AND trashed_at IS NULL',
      variables: [Variable.withString(noteId)],
    ).getSingle();
    return result.read<int>('count');
  }

  /// Search blocks by content using FTS5
  Future<List<NoteBlockModel>> searchBlocks(String noteId, String query) async {
    final matchingIds = await _ftsService.searchBlockIdsInNote(noteId, query);
    if (matchingIds.isEmpty) return [];

    final dbQuery = _db.select(_db.noteBlocks)
      ..where((b) =>
          b.noteId.equals(noteId) &
          b.deleted.equals(0) &
          b.trashedAt.isNull() &
          b.id.isIn(matchingIds))
      ..orderBy([(b) => OrderingTerm.asc(b.orderIndex)]);

    final rows = await dbQuery.get();
    return rows.map(_toModel).toList();
  }

  // ==================== WRITE OPERATIONS ====================

  /// Create a new block
  ///
  /// Per spec: Transaction + oplog entry
  Future<NoteBlockModel> createBlock({
    required String noteId,
    required BlockType blockType,
    required Map<String, dynamic> content,
    required int orderIndex,
    String section = 'main',
  }) async {
    final block = NoteBlockModel.create(
      id: generateId(),
      noteId: noteId,
      blockType: blockType,
      content: content,
      orderIndex: orderIndex,
      section: section,
    );

    final oplogEntry = createInsertOp(block);

    await _db.transaction(() async {
      await _db.into(_db.noteBlocks).insert(_toCompanion(block));
      await _db.into(_db.oplog).insert(_oplogToCompanion(oplogEntry));
      await _ftsService.insertIntoFts(
        blockId: block.id,
        noteId: block.noteId,
        contentJson: jsonEncode(block.content),
      );
    });

    return block;
  }

  /// Create multiple blocks in a single transaction
  ///
  /// Used when creating a new note with initial content
  Future<List<NoteBlockModel>> createBlocks(
    String noteId,
    List<BlockCreateRequest> requests,
  ) async {
    final blocks = <NoteBlockModel>[];
    final oplogEntries = <OplogEntry>[];

    for (var i = 0; i < requests.length; i++) {
      final req = requests[i];
      final block = NoteBlockModel.create(
        id: generateId(),
        noteId: noteId,
        blockType: req.blockType,
        content: req.content,
        orderIndex: req.orderIndex ?? i,
        section: req.section,
      );
      blocks.add(block);
      oplogEntries.add(createInsertOp(block));
    }

    await _db.transaction(() async {
      for (var i = 0; i < blocks.length; i++) {
        await _db.into(_db.noteBlocks).insert(_toCompanion(blocks[i]));
        await _db.into(_db.oplog).insert(_oplogToCompanion(oplogEntries[i]));
        await _ftsService.insertIntoFts(
          blockId: blocks[i].id,
          noteId: blocks[i].noteId,
          contentJson: jsonEncode(blocks[i].content),
        );
      }
    });

    return blocks;
  }

  /// Update a block's content
  ///
  /// Per spec section 4.1:
  /// Editor batches input (300-500ms) before writing
  ///
  /// Per spec: Transaction + oplog entry + version increment
  Future<NoteBlockModel> updateBlock({
    required String id,
    BlockType? blockType,
    Map<String, dynamic>? content,
    int? orderIndex,
  }) async {
    final existing = await getBlockById(id);
    if (existing == null) {
      throw BlockNotFoundException(id);
    }

    final updated = existing.copyWithUpdate(
      blockType: blockType,
      content: content,
      orderIndex: orderIndex,
    );

    final oplogEntry = createUpdateOp(updated);

    await _db.transaction(() async {
      await (_db.update(_db.noteBlocks)..where((b) => b.id.equals(id)))
          .write(_toCompanion(updated));
      await _db.into(_db.oplog).insert(_oplogToCompanion(oplogEntry));
      if (content != null) {
        await _ftsService.updateFts(
          blockId: id,
          noteId: existing.noteId,
          newContentJson: jsonEncode(updated.content),
        );
      }
    });

    return updated;
  }

  /// Update block content only (most common operation)
  Future<NoteBlockModel> updateBlockContent(
    String id,
    Map<String, dynamic> content,
  ) async {
    return updateBlock(id: id, content: content);
  }

  /// Reorder blocks within a note
  ///
  /// This updates multiple blocks' orderIndex values
  Future<void> reorderBlocks(
    String noteId,
    List<String> blockIdsInOrder,
  ) async {
    await _db.transaction(() async {
      for (var i = 0; i < blockIdsInOrder.length; i++) {
        final blockId = blockIdsInOrder[i];
        final existing = await getBlockById(blockId);
        if (existing == null || existing.noteId != noteId) continue;

        if (existing.orderIndex != i) {
          final updated = existing.copyWithUpdate(orderIndex: i);
          final oplogEntry = createUpdateOp(updated);

          await (_db.update(_db.noteBlocks)..where((b) => b.id.equals(blockId)))
              .write(_toCompanion(updated));
          await _db.into(_db.oplog).insert(_oplogToCompanion(oplogEntry));
        }
      }
    });
  }

  /// Insert a block at a specific position
  ///
  /// Shifts all subsequent blocks down
  Future<NoteBlockModel> insertBlockAt({
    required String noteId,
    required int position,
    required BlockType blockType,
    required Map<String, dynamic> content,
  }) async {
    await _db.transaction(() async {
      // Shift existing blocks down
      final blocksToShift = await ((_db.select(_db.noteBlocks)
            ..where((b) =>
                b.noteId.equals(noteId) &
                b.deleted.equals(0) &
                b.trashedAt.isNull() &
                b.orderIndex.isBiggerOrEqualValue(position)))
          .get());

      for (final block in blocksToShift) {
        final model = _toModel(block);
        final updated = model.copyWithUpdate(orderIndex: model.orderIndex + 1);
        final oplogEntry = createUpdateOp(updated);

        await (_db.update(_db.noteBlocks)..where((b) => b.id.equals(block.id)))
            .write(_toCompanion(updated));
        await _db.into(_db.oplog).insert(_oplogToCompanion(oplogEntry));
      }
    });

    // Create the new block
    return createBlock(
      noteId: noteId,
      blockType: blockType,
      content: content,
      orderIndex: position,
    );
  }

  /// Soft delete a block
  Future<void> deleteBlock(String id) async {
    final existing = await getBlockById(id);
    if (existing == null) {
      throw BlockNotFoundException(id);
    }

    final deletedBlock = existing.softDelete();
    final oplogEntry = createDeleteOp(deletedBlock);

    await _db.transaction(() async {
      await _ftsService.removeFromFts(blockId: id);
      await (_db.update(_db.noteBlocks)..where((b) => b.id.equals(id)))
          .write(_toCompanion(deletedBlock));
      await _db.into(_db.oplog).insert(_oplogToCompanion(oplogEntry));
    });
  }

  /// Soft delete all blocks for a note
  ///
  /// Called when a note is deleted
  Future<void> deleteBlocksForNote(String noteId) async {
    final blocks = await getBlocksForNote(noteId);

    await _db.transaction(() async {
      for (final block in blocks) {
        await _ftsService.removeFromFts(blockId: block.id);

        final deletedBlock = block.softDelete();
        final oplogEntry = createDeleteOp(deletedBlock);

        await (_db.update(_db.noteBlocks)..where((b) => b.id.equals(block.id)))
            .write(_toCompanion(deletedBlock));
        await _db.into(_db.oplog).insert(_oplogToCompanion(oplogEntry));
      }
    });
  }

  /// Merge two adjacent blocks
  ///
  /// Combines content of block2 into block1 and deletes block2
  Future<NoteBlockModel> mergeBlocks(String block1Id, String block2Id) async {
    final block1 = await getBlockById(block1Id);
    final block2 = await getBlockById(block2Id);

    if (block1 == null) throw BlockNotFoundException(block1Id);
    if (block2 == null) throw BlockNotFoundException(block2Id);

    // Merge content (simple text concatenation)
    final text1 = block1.plainText;
    final text2 = block2.plainText;
    final mergedContent = {'text': '$text1$text2'};

    late NoteBlockModel result;

    await _db.transaction(() async {
      // Update block1 with merged content
      final updated = block1.copyWithUpdate(content: mergedContent);
      final updateOplog = createUpdateOp(updated);

      await (_db.update(_db.noteBlocks)..where((b) => b.id.equals(block1Id)))
          .write(_toCompanion(updated));
      await _db.into(_db.oplog).insert(_oplogToCompanion(updateOplog));
      await _ftsService.updateFts(
        blockId: block1Id,
        noteId: block1.noteId,
        newContentJson: jsonEncode(mergedContent),
      );

      // Delete block2
      await _ftsService.removeFromFts(blockId: block2Id);

      final deleted = block2.softDelete();
      final deleteOplog = createDeleteOp(deleted);

      await (_db.update(_db.noteBlocks)..where((b) => b.id.equals(block2Id)))
          .write(_toCompanion(deleted));
      await _db.into(_db.oplog).insert(_oplogToCompanion(deleteOplog));

      result = updated;
    });

    return result;
  }

  /// Split a block at a position
  ///
  /// Creates a new block with content after the split position
  Future<(NoteBlockModel, NoteBlockModel)> splitBlock(
    String blockId,
    int splitPosition,
  ) async {
    final existing = await getBlockById(blockId);
    if (existing == null) throw BlockNotFoundException(blockId);

    final text = existing.plainText;
    final text1 = text.substring(0, splitPosition);
    final text2 = text.substring(splitPosition);

    late NoteBlockModel block1;
    late NoteBlockModel block2;

    await _db.transaction(() async {
      // Update existing block with first part
      final updated = existing.copyWithUpdate(content: {'text': text1});
      final updateOplog = createUpdateOp(updated);

      await (_db.update(_db.noteBlocks)..where((b) => b.id.equals(blockId)))
          .write(_toCompanion(updated));
      await _db.into(_db.oplog).insert(_oplogToCompanion(updateOplog));
      await _ftsService.updateFts(
        blockId: blockId,
        noteId: existing.noteId,
        newContentJson: jsonEncode({'text': text1}),
      );

      block1 = updated;
    });

    // Create new block with second part
    block2 = await insertBlockAt(
      noteId: existing.noteId,
      position: existing.orderIndex + 1,
      blockType: existing.blockType,
      content: {'text': text2},
    );

    return (block1, block2);
  }

  // ==================== HELPER METHODS ====================

  /// Convert database row to domain model
  NoteBlockModel _toModel(NoteBlock row) {
    Map<String, dynamic> content;
    try {
      content = jsonDecode(row.contentJson) as Map<String, dynamic>;
    } catch (_) {
      content = {};
    }

    return NoteBlockModel(
      id: row.id,
      noteId: row.noteId,
      blockType: BlockType.fromDbValue(row.blockType),
      content: content,
      orderIndex: row.orderIndex,
      updatedAt: row.updatedAt,
      version: row.version,
      deleted: row.deleted,
      createdAt: row.createdAt,
      section: row.section,
      trashedAt: row.trashedAt,
    );
  }

  /// Convert domain model to database companion
  NoteBlocksCompanion _toCompanion(NoteBlockModel model) {
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

// ==================== REQUEST MODELS ====================

/// Request to create a block
class BlockCreateRequest {
  final BlockType blockType;
  final Map<String, dynamic> content;
  final int? orderIndex;
  final String section;

  const BlockCreateRequest({
    required this.blockType,
    required this.content,
    this.orderIndex,
    this.section = 'main',
  });
}

// ==================== EXCEPTIONS ====================

class BlockNotFoundException implements Exception {
  final String blockId;
  BlockNotFoundException(this.blockId);

  @override
  String toString() => 'Block not found: $blockId';
}
