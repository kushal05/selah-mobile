import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';

import '../../../../core/sync/models/note_block_model.dart';
import '../../../../core/sync/models/note_model.dart';
import '../../../../core/sync/repositories/note_block_repository.dart';
import '../../../../core/sync/repositories/note_repository.dart';
import '../../../../core/sync/repositories/note_tag_repository.dart';
import '../../domain/models/note.dart' as domain;
import '../../domain/repositories/notes_repository.dart';
import '../converters/note_block_converter.dart';
import 'note_revision_repository.dart';

/// Top-level function for compute() — encodes block list to JSON string
/// off the main isolate.
String _encodeBlocksToJson(List<NoteBlockModel> blocks) =>
    jsonEncode(blocks.map((b) => b.toJson()).toList());

/// Top-level function for compute() — decodes NoteModels with documentJson
/// snapshots into domain Notes off the main isolate.
List<domain.Note> _decodeNotesFromSnapshots(List<NoteModel> noteModels) {
  final notes = <domain.Note>[];
  for (final nm in noteModels) {
    try {
      final list = jsonDecode(nm.documentJson!) as List<dynamic>;
      final blocks = list
          .map((e) => NoteBlockModel.fromJson(e as Map<String, dynamic>))
          .toList();
      notes.add(NoteBlockConverter.toDomainNote(nm, blocks));
    } catch (_) {
      // Corrupted or incompatible documentJson — show note with empty document.
      // Blocks will be loaded from DB; documentJson rebuilt on next save.
      notes.add(NoteBlockConverter.toDomainNote(nm, []));
    }
  }
  return notes;
}

/// Adapter that implements [NotesRepository] using sync-enabled repositories.
///
/// Bridges the domain layer (EditorDocument/EditorBlock) to the sync layer
/// (NoteModel/NoteBlockModel) so that all note mutations create oplog entries.
class SyncNotesRepositoryAdapter implements NotesRepository {
  final NoteRepository _noteRepo;
  final NoteBlockRepository _blockRepo;
  final NoteTagRepository _noteTagRepo;
  final NoteRevisionRepository _revisionRepo;
  final String _userId;

  SyncNotesRepositoryAdapter({
    required NoteRepository noteRepo,
    required NoteBlockRepository blockRepo,
    required NoteTagRepository noteTagRepo,
    required NoteRevisionRepository revisionRepo,
    required String userId,
  })  : _noteRepo = noteRepo,
        _blockRepo = blockRepo,
        _noteTagRepo = noteTagRepo,
        _revisionRepo = revisionRepo,
        _userId = userId;

  // ==================== READ OPERATIONS ====================

  @override
  Future<List<domain.Note>> getAllNotes() async {
    final notes = await _noteRepo.getAllNotes(_userId);
    final result = <domain.Note>[];
    for (final note in notes) {
      final blocks = await _getBlocksForNote(note.id, note);
      result.add(NoteBlockConverter.toDomainNote(note, blocks));
    }
    return result;
  }

  @override
  Future<domain.Note?> getNoteById(String id) async {
    final note = await _noteRepo.getNoteById(id);
    if (note == null) return null;
    final blocks = await _getBlocksForNote(id, note);
    return NoteBlockConverter.toDomainNote(note, blocks);
  }

  @override
  Stream<domain.Note?> watchNoteById(String id) {
    return _noteRepo.watchNoteById(id).asyncMap((noteModel) async {
      if (noteModel == null) return null;
      final blocks = await _getBlocksForNote(id, noteModel);
      return NoteBlockConverter.toDomainNote(noteModel, blocks);
    });
  }

  @override
  Stream<List<domain.Note>> watchAllNotes() {
    return _noteRepo.watchAllNotes(_userId).asyncMap((noteModels) async {
      // Separate notes with snapshots (pure computation) from those needing DB
      final withSnapshot = <NoteModel>[];
      final withoutSnapshot = <NoteModel>[];
      for (final nm in noteModels) {
        if (nm.documentJson != null) {
          withSnapshot.add(nm);
        } else {
          withoutSnapshot.add(nm);
        }
      }

      // Decode snapshots off the main isolate via compute()
      final snapshotNotes = withSnapshot.isEmpty
          ? <domain.Note>[]
          : await compute(_decodeNotesFromSnapshots, withSnapshot);

      // DB-dependent notes stay on main isolate (rare — only when snapshot missing)
      final dbNotes = <domain.Note>[];
      for (final nm in withoutSnapshot) {
        final blocks = await _blockRepo.getBlocksForNote(nm.id);
        dbNotes.add(NoteBlockConverter.toDomainNote(nm, blocks));
      }

      return [...snapshotNotes, ...dbNotes];
    });
  }

  // ==================== WRITE OPERATIONS ====================

  @override
  Future<void> createNote(domain.Note note) async {
    // Create the note metadata
    final noteModel = await _noteRepo.createNote(
      id: note.id,
      folderId: note.folderId ?? 'root',
      userId: _userId,
      title: note.title,
      preacherId: note.preacherId,
      noteDate: note.noteDate?.millisecondsSinceEpoch,
    );

    // Create blocks from the editor document
    final blockData = NoteBlockConverter.fromEditorDocument(note.document);
    if (blockData.isNotEmpty) {
      final requests = blockData
          .map((b) => BlockCreateRequest(
                blockType: b.blockType,
                content: b.content,
                orderIndex: b.orderIndex,
                section: b.section,
              ))
          .toList();
      await _blockRepo.createBlocks(noteModel.id, requests);
    }

    // Build documentJson snapshot and touch updatedAt atomically so the
    // preview cache key is aligned with the actual document content.
    await _rebuildDocumentJsonAndTouch(noteModel.id);
  }

  @override
  Future<void> updateNote(domain.Note note) async {
    // Snapshot current state BEFORE applying changes (for revision history).
    try {
      final currentNote = await _noteRepo.getNoteById(note.id);
      if (currentNote != null) {
        final currentBlocks = await _blockRepo.getBlocksForNote(note.id);
        await _revisionRepo.createRevision(currentNote, currentBlocks);
      }
    } catch (_) {
      // Revision creation is best-effort; never block the save.
    }

    // Update note metadata
    await _noteRepo.updateNote(
      id: note.id,
      title: note.title,
      folderId: note.folderId,
      preacherId: note.preacherId,
      noteDate: note.noteDate?.millisecondsSinceEpoch,
      clearPreacher: note.preacherId == null,
      clearNoteDate: note.noteDate == null,
    );

    // Diff blocks: get current state from DB
    final existingBlocks = await _blockRepo.getBlocksForNote(note.id);
    final existingMap = {for (final b in existingBlocks) b.id: b};

    final newBlocks = note.document.blocks;
    final newBlockIds = newBlocks.map((b) => b.id).toSet();
    final existingIds = existingMap.keys.toSet();

    // Delete removed blocks
    for (final id in existingIds.difference(newBlockIds)) {
      await _blockRepo.deleteBlock(id);
    }

    // Assign order indices per section
    final sectionCounters = <String, int>{};

    // Create or update blocks
    for (final editorBlock in newBlocks) {
      final sectionName = editorBlock.section.toDbValue();
      final orderIndex = sectionCounters[sectionName] ?? 0;
      sectionCounters[sectionName] = orderIndex + 1;

      final contentMap = NoteBlockConverter.buildContentMap(editorBlock);
      final syncBlockType = BlockType.values.firstWhere(
        (s) => s.name == editorBlock.type.name,
        orElse: () => BlockType.paragraph,
      );

      if (existingIds.contains(editorBlock.id)) {
        // Skip if nothing changed — avoids redundant oplog entries
        final existing = existingMap[editorBlock.id]!;
        final unchanged = existing.orderIndex == orderIndex &&
            existing.blockType == syncBlockType &&
            const DeepCollectionEquality().equals(existing.content, contentMap);
        if (!unchanged) {
          await _blockRepo.updateBlock(
            id: editorBlock.id,
            blockType: syncBlockType,
            content: contentMap,
            orderIndex: orderIndex,
          );
        }
      } else {
        // Create new block
        await _blockRepo.createBlock(
          noteId: note.id,
          blockType: syncBlockType,
          content: contentMap,
          orderIndex: orderIndex,
          section: sectionName,
        );
      }
    }

    // Rebuild documentJson snapshot and touch updatedAt atomically so the
    // preview cache key is aligned with the actual document content.
    await _rebuildDocumentJsonAndTouch(note.id);
  }

  @override
  Future<void> toggleCheckboxBlock(String noteId, String blockId) async {
    final existing = await _blockRepo.getBlockById(blockId);
    if (existing == null) return;
    final content = Map<String, dynamic>.from(existing.content);
    content['checked'] = !(content['checked'] == true);
    await _blockRepo.updateBlockContent(blockId, content);
    await _rebuildDocumentJsonAndTouch(noteId);
  }

  @override
  Future<void> deleteNote(String id) async {
    await _noteRepo.deleteNote(id);
    // Clean up local-only revision snapshots for the deleted note.
    await _revisionRepo.deleteRevisionsForNote(id);
  }

  @override
  Future<List<domain.Note>> searchNotes(String query) async {
    final notes = await _noteRepo.searchNotes(_userId, query);
    final result = <domain.Note>[];
    for (final note in notes) {
      final blocks = await _getBlocksForNote(note.id, note);
      result.add(NoteBlockConverter.toDomainNote(note, blocks));
    }
    return result;
  }

  @override
  Future<List<domain.Note>> getNotesByPreacher(String preacherId) async {
    final notes = await _noteRepo.getNotesByPreacher(preacherId);
    final result = <domain.Note>[];
    for (final note in notes) {
      final blocks = await _getBlocksForNote(note.id, note);
      result.add(NoteBlockConverter.toDomainNote(note, blocks));
    }
    return result;
  }

  @override
  Future<List<domain.Note>> getNotesWithTag(String tagId) async {
    final noteIds = await _noteTagRepo.getNoteIdsWithTag(tagId);
    final result = <domain.Note>[];
    for (final noteId in noteIds) {
      final note = await getNoteById(noteId);
      if (note != null) result.add(note);
    }
    return result;
  }

  // ==================== TAG OPERATIONS ====================

  @override
  Future<List<String>> getTagsForNote(String noteId) async {
    return _noteTagRepo.getTagIdsForNote(noteId);
  }

  @override
  Future<void> setTagsForNote(String noteId, List<String> tagIds) async {
    await _noteTagRepo.setTagsForNote(noteId, tagIds, _userId);
  }

  @override
  Future<void> addTagToNote(String noteId, String tagId) async {
    await _noteTagRepo.addTagToNote(noteId: noteId, tagId: tagId, userId: _userId);
  }

  @override
  Future<void> removeTagFromNote(String noteId, String tagId) async {
    await _noteTagRepo.removeTagFromNote(noteId, tagId);
  }

  // ==================== MOVE OPERATIONS ====================

  @override
  Future<int> moveNotes(List<String> noteIds, String targetFolderId) async {
    return _noteRepo.moveNotes(noteIds, targetFolderId);
  }

  // ==================== FOLDER OPERATIONS ====================

  @override
  Future<List<domain.Note>> getNotesByFolder(String? folderId) async {
    if (folderId == null) {
      // Root level: get all notes and filter by folderId == 'root'
      final all = await _noteRepo.getAllNotes(_userId);
      final rootNotes = all.where((n) => n.folderId == 'root').toList();
      final result = <domain.Note>[];
      for (final note in rootNotes) {
        final blocks = await _getBlocksForNote(note.id, note);
        result.add(NoteBlockConverter.toDomainNote(note, blocks));
      }
      return result;
    }
    final notes = await _noteRepo.getNotesInFolder(folderId);
    final result = <domain.Note>[];
    for (final note in notes) {
      final blocks = await _getBlocksForNote(note.id, note);
      result.add(NoteBlockConverter.toDomainNote(note, blocks));
    }
    return result;
  }

  @override
  Future<void> moveNotesFromFolder(
      String sourceFolderId, String? targetFolderId) async {
    final notes = await _noteRepo.getNotesInFolder(sourceFolderId);
    for (final note in notes) {
      await _noteRepo.moveNote(note.id, targetFolderId ?? 'root');
    }
  }

  @override
  Future<void> deleteNotesInFolder(String folderId) async {
    await _noteRepo.deleteNotesInFolder(folderId);
  }

  @override
  Future<int> getNoteCountInFolder(String? folderId) async {
    if (folderId == null) {
      final all = await _noteRepo.getAllNotes(_userId);
      return all.where((n) => n.folderId == 'root').length;
    }
    final notes = await _noteRepo.getNotesInFolder(folderId);
    return notes.length;
  }

  // ==================== TRASH OPERATIONS ====================

  @override
  Future<void> trashNote(String id) async {
    await _noteRepo.trashNote(id);
  }

  @override
  Future<void> restoreNote(String id) async {
    await _noteRepo.restoreNote(id);
  }

  // ==================== HYBRID NOTE MODEL HELPERS ====================

  /// Rebuild the documentJson snapshot and update updatedAt atomically.
  ///
  /// Must be used instead of separate touchNote + _rebuildDocumentJson calls.
  /// When those are separate writes, the stream emits once with the new
  /// updatedAt but stale documentJson — the preview cache then stores a stale
  /// value under the new timestamp key, which never gets invalidated.
  Future<void> _rebuildDocumentJsonAndTouch(String noteId) async {
    final blocks = await _blockRepo.getBlocksForNote(noteId);
    final docJson = blocks.isEmpty
        ? null
        : await compute(_encodeBlocksToJson, blocks);
    await _noteRepo.updateDocumentJsonAndTouch(noteId, docJson);
  }

  /// Get blocks for a note, preferring the documentJson snapshot for speed.
  /// Falls back to querying the note_blocks table if documentJson is absent.
  ///
  /// Pass [note] to avoid a redundant DB query when the caller already has it.
  Future<List<NoteBlockModel>> _getBlocksForNote(
    String noteId, [
    NoteModel? note,
  ]) async {
    final docJson = note?.documentJson ??
        (await _noteRepo.getNoteById(noteId))?.documentJson;
    if (docJson != null) {
      try {
        final list = jsonDecode(docJson) as List<dynamic>;
        return list
            .map((e) =>
                NoteBlockModel.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (_) {
        // Corrupted snapshot — fall through to block query
      }
    }
    return _blockRepo.getBlocksForNote(noteId);
  }
}
