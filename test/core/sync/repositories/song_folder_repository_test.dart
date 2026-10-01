// Songbook memberships: a song's songbooks are its folder_id plus its live
// sync_song_folders links, and every read has to agree on that.

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart'
    show BooleanExpressionOperators, driftRuntimeOptions, Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notify/core/database/sync_database.dart';
import 'package:notify/core/sync/models/song_folder_model.dart';
import 'package:notify/core/sync/repositories/entity_access_repository.dart';
import 'package:notify/core/sync/repositories/folder_repository.dart';
import 'package:notify/core/sync/repositories/song_folder_repository.dart';
import 'package:notify/core/sync/repositories/song_repository.dart';
import 'package:notify/core/sync/repositories/song_tag_repository.dart';

const _user = 'u1';
const _device = 'd1';

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  late SyncDatabase db;
  late SongFolderRepository links;
  late FolderRepository folders;
  late SongRepository songs;

  setUp(() async {
    db = SyncDatabase.forTesting(NativeDatabase.memory());
    links = SongFolderRepository(db, _device);
    folders = FolderRepository(db, _device);
    songs = SongRepository(db, _device, EntityAccessRepository(db, _device));
  });
  tearDown(() => db.close());

  Future<String> songbook(String name) async =>
      (await folders.createFolder(name: name, userId: _user, type: 'song')).id;

  Future<List<String>> names(String songId) async =>
      (await links.watchSongbooksForSong(songId).first)
          .map((b) => b.name)
          .toList();

  Future<List<Map<String, Object?>>> ops() async {
    final rows = await (db.select(db.oplog)
          ..where((o) => o.entityType.equals('song_folder')))
        .get();
    return [
      for (final r in rows)
        {'op': r.operation, 'v': r.entityVersion, ...jsonDecode(r.payloadJson)},
    ];
  }

  group('choosePrimary', () {
    const all = {'a', 'b', 'c'};
    test('keeps the current primary while it is still chosen', () {
      expect(SongFolderRepository.choosePrimary('b', ['a', 'b'], live: all),
          'b');
    });
    test('falls back to the first chosen when the primary is unticked', () {
      expect(SongFolderRepository.choosePrimary('c', ['a', 'b'], live: all),
          'a');
    });
    test('is none when nothing is chosen', () {
      expect(SongFolderRepository.choosePrimary('a', [], live: all), isNull);
    });
    test('moves off a primary in Trash when a live songbook is chosen', () {
      // a is in Trash: keeping it primary leaves the song in no visible
      // songbook on builds that only read folder_id.
      expect(
          SongFolderRepository.choosePrimary('a', ['a', 'b'], live: {'b'}),
          'b');
    });
    test('skips a songbook in Trash when the primary is unticked', () {
      expect(
          SongFolderRepository.choosePrimary('p', ['t', 'y'], live: {'y'}),
          'y');
    });
    test('keeps a primary in Trash when nothing live is chosen', () {
      expect(SongFolderRepository.choosePrimary('t', ['t'], live: {}), 't');
    });
  });

  test("a song's songbooks: primary first, links by name, no duplicates",
      () async {
    final zion = await songbook('Zion');
    final ccm = await songbook('CCM');
    final hymns = await songbook('Hymns');
    final song =
        await songs.createSong(userId: _user, title: 'Majesty', folderId: zion);
    // Linking the primary too (as the editor does) must not list it twice.
    await links.setFoldersForSong(song.id, [zion, hymns, ccm], _user);

    expect(await names(song.id), ['Zion', 'CCM', 'Hymns']);
  });

  test('a song saved before memberships existed is still in its folder',
      () async {
    final hymns = await songbook('Hymns');
    final song =
        await songs.createSong(userId: _user, title: 'Old', folderId: hymns);
    expect(await names(song.id), ['Hymns']);
  });

  test('a songbook in Trash keeps its link; a deleted one loses it',
      () async {
    final a = await songbook('A');
    final b = await songbook('B');
    final c = await songbook('C');
    final song = await songs.createSong(userId: _user, title: 'S', folderId: a);
    await links.setFoldersForSong(song.id, [a, b, c], _user);

    await folders.trashFolder(b);
    await folders.deleteFolder(c);

    expect(await names(song.id), ['A']);
    expect(await links.getLinkedFolderIds(song.id), unorderedEquals([a, b]),
        reason: 'B keeps its link so restoring it brings the song back; '
            "C's goes, or it would block the server's GC of C forever");
    final deletes = (await ops()).where((o) => o['op'] == 'DELETE').toList();
    expect(deletes.single['folderId'], c, reason: 'and the delete syncs');
  });

  test("deleting a songbook deletes links into its sub-songbooks", () async {
    final parent = await songbook('Parent');
    final child = (await folders.createFolder(
            name: 'Child', userId: _user, type: 'song', parentId: parent))
        .id;
    final song = await songs.createSong(userId: _user, title: 'S');
    await links.setFoldersForSong(song.id, [child], _user);

    await folders.deleteFolder(parent);

    expect(await links.getLinkedFolderIds(song.id), isEmpty);
  });

  test('permanently deleting a song deletes its links; Trash does not',
      () async {
    final a = await songbook('A');
    final b = await songbook('B');
    final kept = await songs.createSong(userId: _user, title: 'Kept');
    final gone = await songs.createSong(userId: _user, title: 'Gone');
    await links.setFoldersForSong(kept.id, [a], _user);
    await links.setFoldersForSong(gone.id, [a, b], _user);

    await songs.trashSong(kept.id);
    await songs.deleteSong(gone.id);

    expect(await links.getLinkedFolderIds(kept.id), [a]);
    expect(await links.getLinkedFolderIds(gone.id), isEmpty);
    final deletes = (await ops()).where((o) => o['op'] == 'DELETE');
    expect(deletes.map((o) => o['songId']), everyElement(gone.id));
    expect(deletes, hasLength(2));
  });

  test('moving leaves the song in exactly the target songbook', () async {
    final a = await songbook('A');
    final b = await songbook('B');
    final c = await songbook('C');
    final song = await songs.createSong(userId: _user, title: 'S', folderId: a);
    await links.setFoldersForSong(song.id, [a, b], _user);

    await songs.moveSongToSongbook(song.id, c, userId: _user);
    expect(await names(song.id), ['C']);

    await songs.moveSongToSongbook(song.id, null, userId: _user);
    expect(await names(song.id), isEmpty);
    expect((await songs.getSongById(song.id))!.folderId, isNull);
  });

  test('a move that fails part-way changes nothing', () async {
    final a = await songbook('A');
    final b = await songbook('B');
    final song = await songs.createSong(userId: _user, title: 'S', folderId: a);
    await links.setFoldersForSong(song.id, [a], _user);
    final opsBefore = (await db.select(db.oplog).get()).length;

    // Make the link step fail after the primary has been written.
    await db.customStatement('''
      CREATE TRIGGER fail_link_insert BEFORE INSERT ON sync_song_folders
      BEGIN SELECT RAISE(ABORT, 'boom'); END
    ''');
    await expectLater(
        songs.moveSongToSongbook(song.id, b, userId: _user), throwsA(anything));

    expect((await songs.getSongById(song.id))!.folderId, a,
        reason: 'the primary must roll back with the links');
    expect((await db.select(db.oplog).get()).length, opsBefore,
        reason: 'and no half of the move may be queued to sync');
  });

  test('permanently deleting a song deletes its tag links; Trash does not',
      () async {
    final tags = SongTagRepository(db, _device);
    final kept = await songs.createSong(userId: _user, title: 'Kept');
    final gone = await songs.createSong(userId: _user, title: 'Gone');
    await tags.setTagsForSong(kept.id, ['t1'], _user);
    await tags.setTagsForSong(gone.id, ['t1', 't2'], _user);

    await songs.trashSong(kept.id);
    await songs.deleteSong(gone.id);

    expect(await tags.getTagIdsForSong(kept.id), ['t1']);
    expect(await tags.getTagIdsForSong(gone.id), isEmpty);
    final deletes = await (db.select(db.oplog)
          ..where((o) =>
              o.entityType.equals('song_tag') & o.operation.equals('DELETE')))
        .get();
    expect(deletes, hasLength(2), reason: 'and the deletes sync');
    expect(deletes.map((o) => jsonDecode(o.payloadJson)['songId']),
        everyElement(gone.id));
  });

  test('the editor starts with deleted songbooks dropped, Trash kept',
      () async {
    final primary = await songbook('Primary');
    final trashed = await songbook('Trashed');
    final deleted = await songbook('Deleted');
    final other = await songbook('Other');
    final song = await songs.createSong(
        userId: _user, title: 'S', folderId: primary);
    await links.setFoldersForSong(song.id, [trashed, deleted, other], _user);
    await folders.trashFolder(trashed);
    // Deleted on another device: the folder row is gone (deleted = 1) but
    // this device still holds a live link to it.
    await (db.update(db.folders)..where((f) => f.id.equals(deleted)))
        .write(const FoldersCompanion(deleted: Value(1)));

    expect(await links.getSongbookIdsForEditing(song.id),
        [primary, other, trashed]);
  });

  test('setFoldersForSong writes only the difference', () async {
    final a = await songbook('A');
    final b = await songbook('B');
    final c = await songbook('C');
    final song = await songs.createSong(userId: _user, title: 'S');
    await links.setFoldersForSong(song.id, [a, b], _user);
    expect(await ops(), hasLength(2));

    await links.setFoldersForSong(song.id, [b, c], _user);
    final all = await ops();
    expect(all, hasLength(4));
    expect(all.where((o) => o['op'] == 'DELETE').single['folderId'], a);
    expect(await links.getLinkedFolderIds(song.id), unorderedEquals([b, c]));
  });

  test('re-adding a removed link revives the row at a higher version',
      () async {
    final a = await songbook('A');
    final song = await songs.createSong(userId: _user, title: 'S');
    final first =
        await links.addSongToFolder(songId: song.id, folderId: a, userId: _user);
    await links.removeSongFromFolder(song.id, a);
    final again =
        await links.addSongToFolder(songId: song.id, folderId: a, userId: _user);

    expect(again.id, first.id, reason: 'same row, not a second one');
    expect(again.version, 3);
    final last = (await ops()).last;
    expect(last['op'], 'UPDATE');
    expect(last['v'], 3);
    expect(last['deleted'], 0);
  });

  test('payload always carries trashedAt, so the server can clear it', () {
    final m = SongFolderModel.create(
        id: 'x', songId: 's', folderId: 'f', userId: _user);
    expect(m.toJson().containsKey('trashedAt'), isTrue);
    expect(m.toJson()['trashedAt'], isNull);
  });

  test('two devices linking the same pair does not break add or remove',
      () async {
    final a = await songbook('A');
    final song = await songs.createSong(userId: _user, title: 'S');
    for (final id in ['r1', 'r2']) {
      await db.into(db.syncSongFolders).insert(SyncSongFoldersCompanion.insert(
            id: id,
            songId: song.id,
            folderId: a,
            userId: _user,
            updatedAt: 1,
            createdAt: 1,
          ));
    }

    // getSingleOrNull would throw on either of these.
    await links.addSongToFolder(songId: song.id, folderId: a, userId: _user);
    expect(await names(song.id), ['A']);
    await links.removeSongFromFolder(song.id, a);
    expect(await links.getLinkedFolderIds(song.id), isEmpty,
        reason: 'both duplicate rows must go, or the song stays in A');
  });

  test('songbook search matches a song by link, not only by folder_id',
      () async {
    final a = await songbook('A');
    final b = await songbook('B');
    final inA = await songs.createSong(userId: _user, title: 'In A', folderId: a);
    final linkedToA =
        await songs.createSong(userId: _user, title: 'Linked', folderId: b);
    await songs.createSong(userId: _user, title: 'Only B', folderId: b);
    await links.addSongToFolder(
        songId: linkedToA.id, folderId: a, userId: _user);

    final found = await songs.searchSongsFiltered(userId: _user, folderId: a);
    expect(found.map((s) => s.id), unorderedEquals([inA.id, linkedToA.id]));

    // A trashed link no longer counts.
    await (db.update(db.syncSongFolders)
          ..where((r) => r.songId.equals(linkedToA.id)))
        .write(const SyncSongFoldersCompanion(trashedAt: Value(5)));
    final after = await songs.searchSongsFiltered(userId: _user, folderId: a);
    expect(after.map((s) => s.id), [inA.id]);
  });

  test('watchLinksBySong ignores deleted and trashed links', () async {
    final a = await songbook('A');
    final b = await songbook('B');
    final song = await songs.createSong(userId: _user, title: 'S');
    await links.setFoldersForSong(song.id, [a, b], _user);
    await links.removeSongFromFolder(song.id, b);

    expect(await links.watchLinksBySong(_user).first, {
      song.id: {a},
    });
  });

  group('v38 upgrade', () {
    test('creates the table and resets the cursor for one full resync',
        () async {
      final dir = await Directory.systemTemp.createTemp('selah_v38_');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/sync.sqlite');

      final phone = SyncDatabase.forTesting(NativeDatabase(file));
      await phone.customSelect('SELECT 1').get();
      await phone.customStatement('DROP TABLE sync_song_folders');
      await phone.customStatement(
          "UPDATE sync_state SET last_remote_cursor = '1700000000000_op9'");
      await phone.customStatement('PRAGMA user_version = 37');
      await phone.close();

      final updated = SyncDatabase.forTesting(NativeDatabase(file));
      addTearDown(updated.close);
      await updated.customSelect('SELECT 1').get();

      // The table exists and is usable.
      expect(await updated.select(updated.syncSongFolders).get(), isEmpty);
      final cursor = await updated
          .customSelect('SELECT last_remote_cursor FROM sync_state WHERE id = 1')
          .map((r) => r.readNullable<String>('last_remote_cursor'))
          .getSingle();
      expect(cursor, isNull,
          reason: 'older builds skipped song_folder ops but advanced past '
              'them; without a resync those memberships never arrive');
    });

    test('a later open does not reset the cursor again', () async {
      final dir = await Directory.systemTemp.createTemp('selah_v38b_');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/sync.sqlite');

      final first = SyncDatabase.forTesting(NativeDatabase(file));
      await first.customSelect('SELECT 1').get();
      await first.customStatement(
          "UPDATE sync_state SET last_remote_cursor = 'c1'");
      await first.close();

      final again = SyncDatabase.forTesting(NativeDatabase(file));
      addTearDown(again.close);
      final cursor = await again
          .customSelect('SELECT last_remote_cursor FROM sync_state WHERE id = 1')
          .map((r) => r.readNullable<String>('last_remote_cursor'))
          .getSingle();
      expect(cursor, 'c1');
    });
  });
}
