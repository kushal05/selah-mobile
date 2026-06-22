import 'dart:convert';

import '../../../../core/database/sync_database.dart';
import '../../../../core/sync/models/note_block_model.dart';
import '../../../../core/sync/repositories/note_block_repository.dart';
import '../../../../core/sync/repositories/note_repository.dart';
import '../repositories/note_revision_repository.dart';

/// Service that restores a note to a previous revision.
///
/// Restore creates proper oplog entries (UPDATE for note, DELETE+INSERT for
/// blocks) so the restored state syncs to the server. The revision itself
/// is NOT deleted after restore.
class NoteRestoreService {
  final SyncDatabase _db;
  final NoteRepository _noteRepo;
  final NoteBlockRepository _blockRepo;
  final NoteRevisionRepository _revisionRepo;

  NoteRestoreService({
    required SyncDatabase db,
    required NoteRepository noteRepo,
    required NoteBlockRepository blockRepo,
    required NoteRevisionRepository revisionRepo,
  })  : _db = db,
        _noteRepo = noteRepo,
        _blockRepo = blockRepo,
        _revisionRepo = revisionRepo;

  /// Restore a note to the state captured in [revisionId].
  ///
  /// 1. Snapshots the current note state (so the user can undo the restore).
  /// 2. Updates note metadata (bumps version, creates oplog UPDATE).
  /// 3. Soft-deletes all current blocks (creates oplog DELETE per block).
  /// 4. Creates blocks from the snapshot (creates oplog INSERT per block).
  /// 5. Rebuilds the documentJson cache.
  ///
  /// All mutating steps run inside a single transaction for atomicity.
  /// Throws if the revision is not found or corrupt.
  Future<void> restore(String revisionId) async {
    final revision = await _revisionRepo.getRevision(revisionId);
    if (revision == null) {
      throw RevisionNotFoundException(revisionId);
    }

    final snapshot = revision.deserialize();
    if (snapshot == null) {
      throw CorruptRevisionException(revisionId);
    }
    final snapshotNote = snapshot.note;
    final snapshotBlocks = snapshot.blocks;

    // 0. Snapshot the current state before overwriting (best-effort).
    // Uses force: true to bypass the 30-second dedup interval so the
    // pre-restore safety snapshot is always created.
    try {
      final currentNote = await _noteRepo.getNoteById(snapshotNote.id);
      if (currentNote != null) {
        final currentBlocks =
            await _blockRepo.getBlocksForNote(snapshotNote.id);
        await _revisionRepo.createRevision(
          currentNote,
          currentBlocks,
          force: true,
        );
      }
    } catch (_) {
      // Non-fatal: proceed with restore even if pre-snapshot fails.
    }

    // Wrap all mutating steps in a single transaction for atomicity.
    // The inner repo transactions become savepoints within this transaction.
    await _db.transaction(() async {
      // 1. Update note metadata with snapshot values + bump version.
      await _noteRepo.updateNote(
        id: snapshotNote.id,
        title: snapshotNote.title,
        folderId: snapshotNote.folderId,
        preacherId: snapshotNote.preacherId,
        noteDate: snapshotNote.noteDate,
        clearPreacher: snapshotNote.preacherId == null,
        clearNoteDate: snapshotNote.noteDate == null,
      );

      // 2. Soft-delete all current blocks (each gets an oplog DELETE entry).
      await _blockRepo.deleteBlocksForNote(snapshotNote.id);

      // 3. Re-create blocks from the snapshot (each gets an oplog INSERT).
      // createBlocks returns the actual blocks with new IDs and timestamps.
      var createdBlocks = <NoteBlockModel>[];
      if (snapshotBlocks.isNotEmpty) {
        final requests = snapshotBlocks
            .map((b) => BlockCreateRequest(
                  blockType: b.blockType,
                  content: b.content,
                  orderIndex: b.orderIndex,
                  section: b.section,
                ))
            .toList();
        createdBlocks =
            await _blockRepo.createBlocks(snapshotNote.id, requests);
      }

      // 4. Rebuild the documentJson cache from the actual created blocks
      // (not the snapshot blocks, which have stale IDs and timestamps).
      // Use updateDocumentJsonAndTouch for one DB write instead of two.
      // (The stale-cache issue from separate writes doesn't apply here since
      // we're already inside a transaction, but the single write is cleaner.)
      final docJson = createdBlocks.isEmpty
          ? null
          : jsonEncode(createdBlocks.map((b) => b.toJson()).toList());
      await _noteRepo.updateDocumentJsonAndTouch(snapshotNote.id, docJson);
    });
  }
}

class RevisionNotFoundException implements Exception {
  final String revisionId;
  RevisionNotFoundException(this.revisionId);

  @override
  String toString() => 'RevisionNotFoundException: $revisionId';
}

class CorruptRevisionException implements Exception {
  final String revisionId;
  CorruptRevisionException(this.revisionId);

  @override
  String toString() => 'CorruptRevisionException: snapshot JSON is corrupt for $revisionId';
}
