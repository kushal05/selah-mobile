import 'dart:convert';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notify/core/database/services/note_block_fts_service.dart';
import 'package:notify/core/database/sync_database.dart';
import 'package:notify/core/sync/models/note_block_model.dart';
import 'package:notify/core/sync/models/note_model.dart';
import 'package:notify/core/sync/repositories/entity_access_repository.dart';
import 'package:notify/core/sync/repositories/note_block_repository.dart';
import 'package:notify/core/sync/repositories/note_repository.dart';
import 'package:notify/features/notes/data/repositories/note_revision_repository.dart';
import 'package:notify/features/notes/data/services/note_restore_service.dart';

const _userId = 'test-user';
const _deviceId = 'test-device';

void main() {
  late SyncDatabase db;
  late NoteRepository noteRepo;
  late NoteBlockRepository blockRepo;
  late NoteRevisionRepository revisionRepo;

  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  setUp(() async {
    db = SyncDatabase.forTesting(NativeDatabase.memory());
    final fts = NoteBlockFtsService(db);
    final entityAccessRepo = EntityAccessRepository(db, _deviceId);
    noteRepo = NoteRepository(db, _deviceId, fts, entityAccessRepo);
    blockRepo = NoteBlockRepository(db, _deviceId, fts);
    revisionRepo = NoteRevisionRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  /// Helper: create a note with blocks and return the model + blocks.
  Future<(NoteModel, List<NoteBlockModel>)> createTestNote({
    String title = 'Test Note',
    String content = 'Hello world',
  }) async {
    final note = await noteRepo.createNote(
      folderId: 'root',
      userId: _userId,
      title: title,
    );
    final blocks = await blockRepo.createBlocks(note.id, [
      BlockCreateRequest(
        blockType: BlockType.paragraph,
        content: {'text': content},
        orderIndex: 0,
      ),
    ]);
    return (note, blocks);
  }

  group('NoteRevisionRepository', () {
    test('createRevision stores a snapshot', () async {
      final (note, blocks) = await createTestNote();

      await revisionRepo.createRevision(note, blocks);

      final revisions =
          await revisionRepo.watchRevisions(note.id).first;
      expect(revisions, hasLength(1));
      expect(revisions.first.noteId, note.id);

      // Verify snapshot content is valid JSON with note + blocks.
      final snap = jsonDecode(revisions.first.snapshotJson)
          as Map<String, dynamic>;
      expect(snap['note'], isA<Map>());
      expect(snap['blocks'], isA<List>());
      expect((snap['note'] as Map)['title'], 'Test Note');
      expect((snap['blocks'] as List), hasLength(1));
    });

    test('watchRevisions returns newest first', () async {
      final (note, blocks) = await createTestNote();

      // Insert two revisions with timestamps far enough apart to bypass the
      // 30-second deduplication interval.
      final now = DateTime.now().millisecondsSinceEpoch;
      await _insertRevisionRaw(
        db,
        noteId: note.id,
        note: note,
        blocks: blocks,
        createdAt: now - 60000, // 60s ago
      );

      final updatedNote = note.copyWithUpdate(title: 'Updated Title');
      await _insertRevisionRaw(
        db,
        noteId: note.id,
        note: updatedNote,
        blocks: blocks,
        createdAt: now, // now
      );

      final revisions =
          await revisionRepo.watchRevisions(note.id).first;
      expect(revisions, hasLength(2));
      expect(revisions.first.title, 'Updated Title');
      expect(revisions.last.title, 'Test Note');
    });

    test('getRevision returns single revision', () async {
      final (note, blocks) = await createTestNote();
      await revisionRepo.createRevision(note, blocks);

      final revisions =
          await revisionRepo.watchRevisions(note.id).first;
      final rev = await revisionRepo.getRevision(revisions.first.id);

      expect(rev, isNotNull);
      expect(rev!.noteId, note.id);
    });

    test('getRevision returns null for missing ID', () async {
      final rev = await revisionRepo.getRevision('nonexistent');
      expect(rev, isNull);
    });

    test('trims revisions beyond max limit', () async {
      final (note, blocks) = await createTestNote();

      // Insert 55 revisions directly with old timestamps to bypass dedup.
      final baseTime =
          DateTime.now().millisecondsSinceEpoch - 2000000; // ~33 min ago
      for (var i = 0; i < 55; i++) {
        final modified = note.copyWithUpdate(title: 'Rev $i');
        await _insertRevisionRaw(
          db,
          noteId: note.id,
          note: modified,
          blocks: blocks,
          createdAt: baseTime + (i * 1000),
        );
      }

      // The newest raw insert is ~33 min ago, so dedup won't block.
      // createRevision triggers _trimRevisions inside the transaction.
      await revisionRepo.createRevision(
        note.copyWithUpdate(title: 'Trim Trigger'),
        blocks,
      );

      final revisions =
          await revisionRepo.watchRevisions(note.id).first;
      expect(revisions.length, NoteRevisionRepository.maxRevisionsPerNote);
    });

    test('deleteRevisionsForNote removes all revisions', () async {
      final (note, blocks) = await createTestNote();
      final now = DateTime.now().millisecondsSinceEpoch;

      // Insert two revisions via raw helper to bypass dedup.
      await _insertRevisionRaw(db,
          noteId: note.id, note: note, blocks: blocks, createdAt: now - 60000);
      await _insertRevisionRaw(db,
          noteId: note.id, note: note, blocks: blocks, createdAt: now);

      final before = await revisionRepo.watchRevisions(note.id).first;
      expect(before, hasLength(2));

      await revisionRepo.deleteRevisionsForNote(note.id);

      final revisions =
          await revisionRepo.watchRevisions(note.id).first;
      expect(revisions, isEmpty);
    });

    test('skips snapshot if JSON exceeds 1 MB', () async {
      final (note, _) = await createTestNote();

      // Create a block with content > 1 MB.
      final hugeContent = 'x' * (1024 * 1024 + 1);
      final hugeBlocks = [
        NoteBlockModel.create(
          id: 'huge-block',
          noteId: note.id,
          blockType: BlockType.paragraph,
          content: {'text': hugeContent},
          orderIndex: 0,
        ),
      ];

      await revisionRepo.createRevision(note, hugeBlocks);

      final revisions =
          await revisionRepo.watchRevisions(note.id).first;
      expect(revisions, isEmpty);
    });

    test('snapshot deserialize round-trips correctly', () async {
      final (note, blocks) = await createTestNote(
        title: 'Sermon Notes',
        content: 'God is good',
      );

      await revisionRepo.createRevision(note, blocks);

      final revisions =
          await revisionRepo.watchRevisions(note.id).first;
      final snapshot = revisions.first.deserialize();

      expect(snapshot, isNotNull);
      expect(snapshot!.note.title, 'Sermon Notes');
      expect(snapshot.note.id, note.id);
      expect(snapshot.blocks, hasLength(1));
      expect(snapshot.blocks.first.plainText, 'God is good');
    });
  });

  group('NoteRestoreService', () {
    late NoteRestoreService restoreService;

    setUp(() {
      restoreService = NoteRestoreService(
        db: db,
        noteRepo: noteRepo,
        blockRepo: blockRepo,
        revisionRepo: revisionRepo,
      );
    });

    test('restore replaces note content with snapshot', () async {
      // Create initial note.
      final (note, _) = await createTestNote(
        title: 'Original Title',
        content: 'Original content',
      );

      // Snapshot the original state.
      final originalBlocks = await blockRepo.getBlocksForNote(note.id);
      await revisionRepo.createRevision(note, originalBlocks);

      // Modify the note.
      await noteRepo.updateNote(id: note.id, title: 'Modified Title');
      // Soft-delete original block and create a new one.
      for (final b in originalBlocks) {
        await blockRepo.deleteBlock(b.id);
      }
      await blockRepo.createBlock(
        noteId: note.id,
        blockType: BlockType.paragraph,
        content: {'text': 'Modified content'},
        orderIndex: 0,
      );

      // Verify the note is modified.
      final modifiedNote = await noteRepo.getNoteById(note.id);
      expect(modifiedNote!.title, 'Modified Title');

      // Restore to the original revision.
      final revisions =
          await revisionRepo.watchRevisions(note.id).first;
      await restoreService.restore(revisions.first.id);

      // Verify note is restored.
      final restoredNote = await noteRepo.getNoteById(note.id);
      expect(restoredNote!.title, 'Original Title');

      final restoredBlocks = await blockRepo.getBlocksForNote(note.id);
      expect(restoredBlocks, hasLength(1));
      expect(restoredBlocks.first.plainText, 'Original content');
    });

    test('restore bumps note version', () async {
      final (note, blocks) = await createTestNote();
      await revisionRepo.createRevision(note, blocks);

      final versionBefore = (await noteRepo.getNoteById(note.id))!.version;

      final revisions =
          await revisionRepo.watchRevisions(note.id).first;
      await restoreService.restore(revisions.first.id);

      final versionAfter = (await noteRepo.getNoteById(note.id))!.version;
      expect(versionAfter, greaterThan(versionBefore));
    });

    test('restore creates oplog entries', () async {
      final (note, blocks) = await createTestNote();
      await revisionRepo.createRevision(note, blocks);

      // Count oplog entries before restore.
      final oplogBefore = await db.getUnsyncedOps();
      final countBefore = oplogBefore.length;

      final revisions =
          await revisionRepo.watchRevisions(note.id).first;
      await restoreService.restore(revisions.first.id);

      // Should have new oplog entries (UPDATE for note + DELETE for old blocks + INSERT for restored blocks + touchNote).
      final oplogAfter = await db.getUnsyncedOps();
      expect(oplogAfter.length, greaterThan(countBefore));
    });

    test('revision creation does NOT create oplog entries', () async {
      final (note, blocks) = await createTestNote();

      final oplogBefore = await db.getUnsyncedOps();
      final countBefore = oplogBefore.length;

      await revisionRepo.createRevision(note, blocks);

      final oplogAfter = await db.getUnsyncedOps();
      expect(oplogAfter.length, countBefore,
          reason: 'Revision creation should not touch the oplog');
    });

    test('restore does not delete the revision entry', () async {
      final (note, blocks) = await createTestNote();
      await revisionRepo.createRevision(note, blocks);

      final revisions =
          await revisionRepo.watchRevisions(note.id).first;
      expect(revisions, hasLength(1));

      await restoreService.restore(revisions.first.id);

      // Revision should still exist.
      final revisionsAfter =
          await revisionRepo.watchRevisions(note.id).first;
      expect(revisionsAfter, isNotEmpty);
    });

    test('restore throws for nonexistent revision', () async {
      expect(
        () => restoreService.restore('nonexistent'),
        throwsA(isA<RevisionNotFoundException>()),
      );
    });

    test('restore creates pre-restore snapshot of current state', () async {
      final (note, blocks) = await createTestNote(
        title: 'Original',
        content: 'Original content',
      );

      // Snapshot the original state.
      final originalBlocks = await blockRepo.getBlocksForNote(note.id);
      await revisionRepo.createRevision(note, originalBlocks);

      // Modify the note so current state differs from the snapshot.
      await noteRepo.updateNote(id: note.id, title: 'Modified');

      final revisions =
          await revisionRepo.watchRevisions(note.id).first;
      expect(revisions, hasLength(1));

      // Restore to the original snapshot.
      await restoreService.restore(revisions.first.id);

      // Should now have 2 revisions: the original + the pre-restore snapshot
      // of the modified state.
      final revisionsAfter =
          await revisionRepo.watchRevisions(note.id).first;
      expect(revisionsAfter, hasLength(2),
          reason: 'Pre-restore snapshot should be created');

      // The newest revision should be the pre-restore snapshot with the
      // modified title.
      expect(revisionsAfter.first.title, 'Modified');
    });

    test('restore throws for corrupt revision snapshot', () async {
      // Insert a revision with invalid JSON directly.
      await db.into(db.noteRevisions).insert(
            NoteRevisionsCompanion.insert(
              id: 'corrupt-rev',
              noteId: 'some-note',
              snapshotJson: '{invalid json!!!',
              createdAt: DateTime.now().millisecondsSinceEpoch,
            ),
          );

      expect(
        () => restoreService.restore('corrupt-rev'),
        throwsA(isA<CorruptRevisionException>()),
      );
    });
  });
}

/// Insert a revision row directly into the DB, bypassing the deduplication
/// interval. Used by tests that need multiple revisions in quick succession.
Future<void> _insertRevisionRaw(
  SyncDatabase db, {
  required String noteId,
  required NoteModel note,
  required List<NoteBlockModel> blocks,
  required int createdAt,
}) async {
  final snapshot = jsonEncode({
    'note': note.toJson(),
    'blocks': blocks.map((b) => b.toJson()).toList(),
  });
  await db.into(db.noteRevisions).insert(
        NoteRevisionsCompanion.insert(
          id: 'rev-${DateTime.now().microsecondsSinceEpoch}-$createdAt',
          noteId: noteId,
          snapshotJson: snapshot,
          createdAt: createdAt,
        ),
      );
}
