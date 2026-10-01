// A tag a note still writes as `#name` is not deleted. Notes derive their tags
// from their text on every save, so deleting it would only last until the next
// edit of that note: the tag would come back, links and all.
//
// "Writes" is read exactly as the editor reads it — block plain text, Bible
// reference blocks skipped, the same InlineTagParser — so the refusal and the
// re-creation it prevents can never disagree.

import 'package:drift/drift.dart'
    show
        ApplyInterceptor,
        QueryExecutor,
        QueryInterceptor,
        Value,
        driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notify/core/database/services/note_block_fts_service.dart';
import 'package:notify/core/database/sync_database.dart';
import 'package:notify/core/sync/models/note_block_model.dart';
import 'package:notify/core/sync/repositories/entity_access_repository.dart';
import 'package:notify/core/sync/repositories/folder_repository.dart';
import 'package:notify/core/sync/repositories/note_block_repository.dart';
import 'package:notify/core/sync/repositories/note_repository.dart';
import 'package:notify/core/sync/repositories/person_repository.dart';
import 'package:notify/core/sync/repositories/prayer_repository.dart';
import 'package:notify/core/sync/repositories/preacher_repository.dart';
import 'package:notify/core/sync/repositories/promise_repository.dart';
import 'package:notify/core/sync/repositories/song_repository.dart';
import 'package:notify/core/sync/repositories/tag_repository.dart';
import 'package:notify/core/sync/services/trash_purge_service.dart';

const _user = 'u1';
const _device = 'd1';

/// Counts the reads of note text: the scan that decides whether a tag is
/// still written.
class _NoteScans extends QueryInterceptor {
  var count = 0;

  @override
  Future<List<Map<String, Object?>>> runSelect(
      QueryExecutor executor, String statement, List<Object?> args) {
    if (statement.contains('FROM note_blocks b')) count++;
    return super.runSelect(executor, statement, args);
  }
}

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  late SyncDatabase db;
  late _NoteScans scans;
  late TagRepository tags;
  late NoteRepository notes;
  late NoteBlockRepository blocks;
  late String folderId;

  setUp(() async {
    scans = _NoteScans();
    db = SyncDatabase.forTesting(NativeDatabase.memory().interceptWith(scans));
    final fts = NoteBlockFtsService(db);
    tags = TagRepository(db, _device);
    notes = NoteRepository(db, _device, fts, EntityAccessRepository(db, _device));
    blocks = NoteBlockRepository(db, _device, fts);
    folderId = (await FolderRepository(db, _device)
            .createFolder(name: 'Sermons', userId: _user))
        .id;
  });
  tearDown(() => db.close());

  /// A note whose one block reads [text]. Returns (noteId, blockId).
  Future<(String, String)> note(String text,
      {BlockType type = BlockType.paragraph}) async {
    final n = await notes.createNote(
        folderId: folderId, userId: _user, title: 'N');
    final b = await blocks.createBlock(
        noteId: n.id, blockType: type, content: {'text': text}, orderIndex: 0);
    return (n.id, b.id);
  }

  Future<bool> stillLive(String tagId) async =>
      (await tags.getTagById(tagId))!.deleted == 0;

  test('refused while a note writes #name, and nothing changes', () async {
    final faith = await tags.createTag(userId: _user, name: 'faith');
    await note('trusting #Faith today'); // case folds, as in the editor
    await note('more #faith');
    await db.customStatement(
      'INSERT INTO sync_song_tags (id, song_id, tag_id, user_id, updated_at, '
      'version, deleted, created_at) VALUES (?, ?, ?, ?, 1, 1, 0, 1)',
      ['st1', 's1', faith.id, _user],
    );
    final opsBefore = (await db.select(db.oplog).get()).length;

    await expectLater(
      tags.deleteTag(faith.id),
      throwsA(isA<TagStillWrittenException>()
          .having((e) => e.name, 'name', 'faith')
          .having((e) => e.noteCount, 'noteCount', 2)),
    );

    expect(await stillLive(faith.id), isTrue);
    final link = await (db.select(db.syncSongTags)
          ..where((t) => t.id.equals('st1')))
        .getSingle();
    expect(link.deleted, 0, reason: 'its links must survive too');
    expect((await db.select(db.oplog).get()).length, opsBefore);
  });

  test('only a whole #word counts, as the editor reads it', () async {
    final faith = await tags.createTag(userId: _user, name: 'faith');
    await note('#faithful and #faith-filled'); // longer words
    await note('see example.com#faith'); // no space before the #
    await note('just faith, no hash');
    await note('#faith', type: BlockType.bibleReference); // skipped by editor

    await tags.deleteTag(faith.id);

    expect(await stillLive(faith.id), isFalse);
  });

  test('a note in Trash, or a deleted block, does not hold the tag', () async {
    final faith = await tags.createTag(userId: _user, name: 'faith');
    final (trashed, _) = await note('#faith in the bin');
    final (_, gone) = await note('#faith removed');
    await notes.trashNote(trashed);
    await blocks.deleteBlock(gone);

    await tags.deleteTag(faith.id);

    expect(await stillLive(faith.id), isFalse);
  });

  test('a note trashed elsewhere, blocks not yet, does not hold the tag',
      () async {
    // trashNote trashes the blocks too, so the test above cannot tell the
    // note-level check from the block-level one. A trash synced from another
    // device can land before its block updates do; then only the note says so.
    final faith = await tags.createTag(userId: _user, name: 'faith');
    final (noteId, _) = await note('#faith');
    await (db.update(db.syncNotes)..where((n) => n.id.equals(noteId)))
        .write(const SyncNotesCompanion(trashedAt: Value(5)));

    await tags.deleteTag(faith.id);

    expect(await stillLive(faith.id), isFalse);
  });

  test("another user's notes do not hold the tag", () async {
    final faith = await tags.createTag(userId: _user, name: 'faith');
    final other = await notes.createNote(
        folderId: folderId, userId: 'someone-else', title: 'N');
    await blocks.createBlock(
        noteId: other.id,
        blockType: BlockType.paragraph,
        content: {'text': '#faith'},
        orderIndex: 0);

    await tags.deleteTag(faith.id);

    expect(await stillLive(faith.id), isFalse);
  });

  test('once the text is gone, the delete goes through', () async {
    final faith = await tags.createTag(userId: _user, name: 'faith');
    final (_, blockId) = await note('#faith');
    await expectLater(
        tags.deleteTag(faith.id), throwsA(isA<TagStillWrittenException>()));

    await blocks.updateBlockContent(blockId, {'text': 'faith'});
    await tags.deleteTag(faith.id);

    expect(await stillLive(faith.id), isFalse);
  });

  test('spans text is read too', () async {
    final n = await notes.createNote(
        folderId: folderId, userId: _user, title: 'N');
    await blocks.createBlock(
      noteId: n.id,
      blockType: BlockType.paragraph,
      content: {
        'spans': [
          {'text': 'by '},
          {'text': '#faith'},
        ],
      },
      orderIndex: 0,
    );

    expect(await tags.countNotesWritingTag('faith', _user), 1);
  });

  group('merge', () {
    // Tags are the user's: the app does not rewrite `#faith` to `#belief`, so
    // a merge would last only until the next save of a note writing #faith.
    test('refused while a note writes the source, and nothing changes',
        () async {
      final faith = await tags.createTag(userId: _user, name: 'faith');
      final belief = await tags.createTag(userId: _user, name: 'belief');
      await note('by #faith alone');
      await db.customStatement(
        'INSERT INTO sync_song_tags (id, song_id, tag_id, user_id, '
        'updated_at, version, deleted, created_at) '
        'VALUES (?, ?, ?, ?, 1, 1, 0, 1)',
        ['st1', 's1', faith.id, _user],
      );
      final opsBefore = (await db.select(db.oplog).get()).length;

      await expectLater(
        tags.mergeTags(sourceTagId: faith.id, targetTagId: belief.id),
        throwsA(isA<TagStillWrittenException>()
            .having((e) => e.name, 'name', 'faith')
            .having((e) => e.noteCount, 'noteCount', 1)),
      );

      expect(await stillLive(faith.id), isTrue);
      final link = await (db.select(db.syncSongTags)
            ..where((t) => t.id.equals('st1')))
          .getSingle();
      expect(link.tagId, faith.id, reason: 'nothing re-pointed');
      expect(link.deleted, 0);
      expect((await db.select(db.oplog).get()).length, opsBefore);
    });

    test('a target that notes write is fine to merge into', () async {
      final faith = await tags.createTag(userId: _user, name: 'faith');
      final belief = await tags.createTag(userId: _user, name: 'belief');
      await note('#belief');

      await tags.mergeTags(sourceTagId: faith.id, targetTagId: belief.id);

      expect(await stillLive(faith.id), isFalse);
      expect(await stillLive(belief.id), isTrue);
    });

    test('once the text is gone, the merge goes through', () async {
      final faith = await tags.createTag(userId: _user, name: 'faith');
      final belief = await tags.createTag(userId: _user, name: 'belief');
      final (_, blockId) = await note('#faith');
      await blocks.updateBlockContent(blockId, {'text': '#belief'});

      await tags.mergeTags(sourceTagId: faith.id, targetTagId: belief.id);

      expect(await stillLive(faith.id), isFalse);
    });
  });

  group('deleteTags (Empty Trash, the purge)', () {
    test('deletes the rest, keeps the written ones, and says which', () async {
      final faith = await tags.createTag(userId: _user, name: 'faith');
      final hope = await tags.createTag(userId: _user, name: 'hope');
      final love = await tags.createTag(userId: _user, name: 'love');
      await note('#faith and #Love');
      await note('#faith again');

      final result = await tags.deleteTags([faith.id, hope.id, love.id]);

      expect(result.deleted, 1);
      expect(
          {for (final k in result.kept) k.name: k.noteCount},
          {'faith': 2, 'love': 1});
      expect(await stillLive(faith.id), isTrue);
      expect(await stillLive(hope.id), isFalse);
      expect(await stillLive(love.id), isTrue);
    });

    test('reads the notes once, not once per tag', () async {
      final ids = [
        for (final name in ['a', 'b', 'c', 'd', 'e'])
          (await tags.createTag(userId: _user, name: name)).id,
      ];
      await note('#a');
      scans.count = 0;

      await tags.deleteTags(ids);

      expect(scans.count, 1);
    });

    test('agrees with deleteTag on what counts as written', () async {
      final faith = await tags.createTag(userId: _user, name: 'faith');
      await note('#faithful, example.com#faith');
      await note('#faith', type: BlockType.bibleReference);

      expect((await tags.deleteTags([faith.id])).deleted, 1);
    });
  });

  test('the Trash purge skips a tag still written, and carries on', () async {
    final access = EntityAccessRepository(db, _device);
    final purge = TrashPurgeService(
      noteRepo: notes,
      folderRepo: FolderRepository(db, _device),
      prayerRepo: PrayerRepository(db, _device, access),
      promiseRepo: PromiseRepository(db, _device, access),
      personRepo: PersonRepository(db, _device),
      songRepo: SongRepository(db, _device, access),
      preacherRepo: PreacherRepository(db, _device),
      tagRepo: tags,
      userId: _user,
    );
    final kept = await tags.createTag(userId: _user, name: 'faith');
    final purged = await tags.createTag(userId: _user, name: 'hope');
    await note('#faith');
    for (final t in [kept, purged]) {
      await tags.trashTag(t.id);
      await (db.update(db.syncTags)..where((r) => r.id.equals(t.id)))
          .write(const SyncTagsCompanion(trashedAt: Value(1))); // long ago
    }

    final count = await purge.purgeExpiredItems();

    expect(await stillLive(kept.id), isTrue);
    expect(await stillLive(purged.id), isFalse);
    expect(count, 1);
  });
}
