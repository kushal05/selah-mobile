// Ranked song search through the repository, against a real database: the
// SQL hard filters, the live-tag join and SongSearchRanker together.

import 'dart:convert';

import 'package:drift/drift.dart' show driftRuntimeOptions, Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notify/core/database/sync_database.dart';
import 'package:notify/core/sync/repositories/entity_access_repository.dart';
import 'package:notify/core/sync/repositories/song_repository.dart';
import 'package:notify/core/sync/repositories/song_tag_repository.dart';
import 'package:notify/core/sync/repositories/tag_repository.dart';

const _user = 'u1';
const _device = 'd1';

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  late SyncDatabase db;
  late SongRepository songs;
  late TagRepository tags;
  late SongTagRepository links;

  setUp(() {
    db = SyncDatabase.forTesting(NativeDatabase.memory());
    songs = SongRepository(db, _device, EntityAccessRepository(db, _device));
    tags = TagRepository(db, _device);
    links = SongTagRepository(db, _device);
  });
  tearDown(() => db.close());

  Future<String> song(String title, {String lyrics = ''}) async =>
      (await songs.createSong(userId: _user, title: title, lyrics: lyrics)).id;

  Future<String> tag(String name) async =>
      (await tags.createTag(userId: _user, name: name)).id;

  /// Links [songId] to [tagId] with [weight] (weights come from the rating
  /// pass on the server; the app has no way to set them).
  Future<String> link(String songId, String tagId, int weight) async {
    final l = await links.addTagToSong(songId: songId, tagId: tagId, userId: _user);
    await (db.update(db.syncSongTags)..where((r) => r.id.equals(l.id)))
        .write(SyncSongTagsCompanion(weight: Value(weight)));
    return l.id;
  }

  Future<List<String>> titles({String? q, List<String>? tagIds}) async => [
        for (final s in await songs.searchSongsFiltered(
            userId: _user, textQuery: q, tagIds: tagIds))
          s.title,
      ];

  test('a typed query: title, then tag by weight, then lyrics', () async {
    final grace = await tag('grace');
    await song('Unrelated', lyrics: 'nothing here');
    final lyricsOnly = await song('Broken Vessels', lyrics: 'amazing grace');
    final strongTag = await song('Your Love Never Fails');
    final weakTag = await song('Oceans');
    await song('Amazing Grace');
    await link(strongTag, grace, 3);
    await link(weakTag, grace, 1);
    await link(lyricsOnly, grace, 1);

    expect(await titles(q: 'grace'), [
      'Amazing Grace', // title
      'Your Love Never Fails', // tag 3×3
      'Broken Vessels', // tag 1×3, and lyrics: the tag tier decides first
      'Oceans', // tag 1×3, no lyrics
    ]);
  });

  test('the tag filter orders by the weight on the chosen tags, then count', () async {
    final grace = await tag('grace');
    final healing = await tag('healing');
    final a = await song('A one light');
    final b = await song('B one strong');
    final c = await song('C two');
    await song('D untagged');
    await link(a, grace, 1);
    await link(b, grace, 3);
    await link(c, grace, 2);
    await link(c, healing, 1);

    expect(await titles(tagIds: [grace, healing]),
        ['C two', 'B one strong', 'A one light'],
        reason: 'C and B both carry 3; C carries two of the chosen tags');
  });

  test('a trashed link or a deleted tag does not count', () async {
    final grace = await tag('grace');
    final hope = await tag('hope');
    final trashedLink = await song('Trashed Link');
    final deletedTag = await song('Deleted Tag');
    final linkId = await link(trashedLink, grace, 3);
    await link(deletedTag, hope, 3);
    await (db.update(db.syncSongTags)..where((r) => r.id.equals(linkId)))
        .write(const SyncSongTagsCompanion(trashedAt: Value(5)));
    await (db.update(db.syncTags)..where((r) => r.id.equals(hope)))
        .write(const SyncTagsCompanion(deleted: Value(1)));

    expect(await titles(tagIds: [grace]), isEmpty,
        reason: 'the filter used to count trashed links');
    expect(await titles(tagIds: [hope]), isEmpty);
    expect(await titles(q: 'grace'), isEmpty);
    expect(await titles(q: 'hope'), isEmpty);
  });

  test('global search finds a song by a real tag, not by the legacy text', () async {
    final surrender = await tag('surrender');
    final tagged = await song('I Give You My Heart', lyrics: 'all I am');
    await link(tagged, surrender, 2);
    final legacy = await song('Legacy Only');
    await (db.update(db.songs)..where((s) => s.id.equals(legacy)))
        .write(const SongsCompanion(tags: Value('surrender')));

    final found = await songs.searchSongs('surrender', _user);
    expect(found.map((s) => s.title), ['I Give You My Heart']);
  });

  test("a song's tags count even if the link's own user id differs", () async {
    // Links are matched by the song's owner, the same test the song query
    // uses: a song that is found always brings its tags.
    final grace = await tag('grace');
    final s = await song('No Title Match');
    final id = await link(s, grace, 3);
    await (db.update(db.syncSongTags)..where((r) => r.id.equals(id)))
        .write(const SyncSongTagsCompanion(userId: Value('someone-else')));

    final r = await songs.searchSongsRanked(userId: _user, textQuery: 'grace');
    expect(r.single.tagScore, 9);
  });

  test('a stored weight outside 1-3 is clamped', () async {
    final grace = await tag('grace');
    final s = await song('X');
    await link(s, grace, 9);

    final r = await songs.searchSongsRanked(userId: _user, textQuery: 'grace');
    expect(r.single.tagScore, 9, reason: 'clamped to 3, × quality 3');
  });

  group('re-adding a removed tag', () {
    test('revives the same row at a higher version, as an UPDATE', () async {
      final grace = await tag('grace');
      final s = await song('X');
      final first = await links.addTagToSong(songId: s, tagId: grace, userId: _user);
      await links.removeTagFromSong(s, grace);
      final again = await links.addTagToSong(songId: s, tagId: grace, userId: _user);

      expect(again.id, first.id);
      expect(again.version, 3);
      final op = (await (db.select(db.oplog)
                ..where((o) => o.entityType.equals('song_tag')))
              .get())
          .last;
      expect(op.operation, 'UPDATE',
          reason: 'an INSERT at version 1 under the old id was ignored by the '
              'server, so the tag stayed removed on other devices');
      final payload = jsonDecode(op.payloadJson) as Map<String, dynamic>;
      expect(payload['deleted'], 0);
      expect(payload.containsKey('trashedAt'), isTrue,
          reason: 'sent even when null, or the server keeps it trashed');
      expect(payload['weight'], 2);
    });

    test('two rows for the same pair: add finds one, remove takes both', () async {
      final grace = await tag('grace');
      final s = await song('X');
      for (final id in ['r1', 'r2']) {
        await db.into(db.syncSongTags).insert(SyncSongTagsCompanion.insert(
              id: id, songId: s, tagId: grace, userId: _user, updatedAt: 1, createdAt: 1));
      }

      await links.addTagToSong(songId: s, tagId: grace, userId: _user);
      expect(await links.getTagIdsForSong(s), hasLength(2));
      await links.removeTagFromSong(s, grace);
      expect(await links.getTagIdsForSong(s), isEmpty,
          reason: 'getSingleOrNull threw on duplicates; one left behind kept the tag');
    });
  });
}
