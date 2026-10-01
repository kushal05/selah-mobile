// Deleting a tag for good retires its links on notes, songs, prayers and
// promises. Left live they were invisible in the app but kept the server's GC
// from ever hard-deleting the tag. Trash keeps them, so a restore brings the
// tag back on everything it was on.

import 'dart:convert';

import 'package:drift/drift.dart' show Variable, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notify/core/database/sync_database.dart';
import 'package:notify/core/sync/repositories/tag_repository.dart';

const _user = 'u1';

/// Every junction table on sync_tags, its owner column and oplog type. Kept
/// here rather than read from TagRepository, so a table dropped from the
/// repository's list fails this test instead of silently shrinking it.
const _junctions = [
  ('sync_note_tags', 'note_id', 'note_tag'),
  ('sync_song_tags', 'song_id', 'song_tag'),
  ('sync_prayer_tags', 'prayer_id', 'prayer_tag'),
  ('sync_promise_tags', 'promise_id', 'promise_tag'),
];

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  late SyncDatabase db;
  late TagRepository tags;

  setUp(() {
    db = SyncDatabase.forTesting(NativeDatabase.memory());
    tags = TagRepository(db, 'd1');
  });
  tearDown(() => db.close());

  /// Links [tagId] to one owner in every junction table, created at [at].
  Future<void> linkEverywhere(String tagId, {required int at}) async {
    for (final (table, owner, _) in _junctions) {
      await db.customStatement(
        'INSERT INTO $table (id, $owner, tag_id, user_id, updated_at, '
        'version, deleted, created_at) VALUES (?, ?, ?, ?, ?, 1, 0, ?)',
        ['$table-$tagId', 'owner-$table', tagId, _user, at, at],
      );
    }
  }

  Future<Map<String, int>> liveLinks(String tagId) async => {
        for (final (table, _, _) in _junctions)
          table: (await db
                  .customSelect(
                      'SELECT COUNT(*) c FROM $table '
                      'WHERE tag_id = ? AND deleted = 0',
                      variables: [Variable.withString(tagId)])
                  .getSingle())
              .read<int>('c'),
      };

  Future<List<Map<String, dynamic>>> linkDeletes() async {
    final rows = await (db.select(db.oplog)
          ..where((o) => o.operation.equals('DELETE')))
        .get();
    return [
      for (final r in rows)
        if (r.entityType != 'tag')
          {'type': r.entityType, ...jsonDecode(r.payloadJson)},
    ];
  }

  test('deleting a tag retires its links in all four tables', () async {
    final faith = await tags.createTag(userId: _user, name: 'faith');
    await linkEverywhere(faith.id, at: 111);

    await tags.deleteTag(faith.id);

    expect((await liveLinks(faith.id)).values, everyElement(0));
    final deletes = await linkDeletes();
    expect(deletes.map((d) => d['type']),
        unorderedEquals(_junctions.map((j) => j.$3)),
        reason: 'one synced delete per link, in each table');
    for (final d in deletes) {
      expect(d['version'], 2);
      expect(d['deleted'], 1);
      expect(d['createdAt'], 111, reason: 'the link keeps its creation time');
    }
  });

  test("another tag's links are left alone", () async {
    final faith = await tags.createTag(userId: _user, name: 'faith');
    final hope = await tags.createTag(userId: _user, name: 'hope');
    await linkEverywhere(faith.id, at: 1);
    await linkEverywhere(hope.id, at: 1);

    await tags.deleteTag(faith.id);

    expect((await liveLinks(hope.id)).values, everyElement(1));
  });

  test('a tag in Trash keeps its links, so a restore brings them back',
      () async {
    final faith = await tags.createTag(userId: _user, name: 'faith');
    await linkEverywhere(faith.id, at: 1);

    await tags.trashTag(faith.id);

    expect((await liveLinks(faith.id)).values, everyElement(1));
    expect(await linkDeletes(), isEmpty);
  });

  test('purging a tag from Trash retires its links', () async {
    final faith = await tags.createTag(userId: _user, name: 'faith');
    await linkEverywhere(faith.id, at: 1);
    await tags.trashTag(faith.id);

    await tags.deleteTag(faith.id);

    expect((await liveLinks(faith.id)).values, everyElement(0));
  });

  test("a merge's retired links keep their creation time", () async {
    final faith = await tags.createTag(userId: _user, name: 'faith');
    final belief = await tags.createTag(userId: _user, name: 'belief');
    await linkEverywhere(faith.id, at: 222);

    await tags.mergeTags(sourceTagId: faith.id, targetTagId: belief.id);

    final deletes = await linkDeletes();
    expect(deletes, hasLength(4));
    expect(deletes.map((d) => d['createdAt']), everyElement(222),
        reason: 'it was sent as the time of the merge, rewriting the date '
            'on the server');
    expect((await liveLinks(belief.id)).values, everyElement(1));
  });
}
