// Tags are lowercase, so "Faith" and "faith" are one tag rather than two.
//
// Normalising new writes does not touch what is already stored, so the v33
// migration folds existing tags together. Two things make that delicate: the
// survivor must be the same row on every device, and every junction table has
// to come along — a merge that forgets one leaves rows pointing at a tag that
// has just been deleted, and the tag silently falls off those items.

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notify/core/database/sync_database.dart';
import 'package:notify/core/sync/repositories/tag_repository.dart';

const _userId = 'test-user';
const _deviceId = 'test-device';

void main() {
  late SyncDatabase db;
  late TagRepository tags;

  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  setUp(() async {
    db = SyncDatabase.forTesting(NativeDatabase.memory());
    tags = TagRepository(db, _deviceId);
  });

  tearDown(() async => db.close());

  Future<void> seedTag(String id, String name, {int createdAt = 0}) =>
      db.customStatement(
        'INSERT INTO sync_tags (id, user_id, name, updated_at, version, '
        'deleted, created_at) VALUES (?, ?, ?, 0, 1, 0, ?)',
        [id, _userId, name, createdAt],
      );

  Future<void> seedLink(String table, String ownerCol, String rowId,
          String ownerId, String tagId) =>
      db.customStatement(
        'INSERT INTO $table (id, $ownerCol, tag_id, user_id, updated_at, '
        'version, deleted, created_at) VALUES (?, ?, ?, ?, 0, 1, 0, 0)',
        [rowId, ownerId, tagId, _userId],
      );

  Future<List<String>> liveTagNames() async {
    final rows = await db
        .customSelect('SELECT name FROM sync_tags WHERE deleted = 0 '
            'ORDER BY name')
        .get();
    return rows.map((r) => r.read<String>('name')).toList();
  }

  Future<List<String>> liveTagIdsOn(String table) async {
    final rows = await db
        .customSelect('SELECT tag_id FROM $table WHERE deleted = 0')
        .get();
    return rows.map((r) => r.read<String>('tag_id')).toList();
  }

  group('normalising on write', () {
    test('a new tag is stored lowercase', () async {
      final tag = await tags.createTag(userId: _userId, name: '  Faith  ');
      expect(tag.name, 'faith');
    });

    test('getOrCreateTag finds a tag stored before the rule existed',
        () async {
      // The row an older build left behind.
      await seedTag('t1', 'Faith');

      final tag = await tags.getOrCreateTag('faith', _userId);

      expect(tag.id, 't1', reason: 'a second tag was created beside it');
      expect(await liveTagNames(), ['Faith'],
          reason: 'lookup should find it, not rewrite it');
    });

    test('differing case resolves to one tag', () async {
      final a = await tags.getOrCreateTag('Faith', _userId);
      final b = await tags.getOrCreateTag('FAITH', _userId);
      final c = await tags.getOrCreateTag('faith', _userId);

      expect({a.id, b.id, c.id}, hasLength(1));
    });
  });

  group('the v33 fold', () {
    test('keeps the oldest row, so every device picks the same survivor',
        () async {
      await seedTag('t-newest', 'FAITH', createdAt: 300);
      await seedTag('t-oldest', 'Faith', createdAt: 100);
      await seedTag('t-middle', 'faith', createdAt: 200);

      await db.foldTagsToLowercase();

      final rows = await db
          .customSelect('SELECT id, name FROM sync_tags WHERE deleted = 0')
          .get();
      expect(rows, hasLength(1));
      expect(rows.single.read<String>('id'), 't-oldest');
      expect(rows.single.read<String>('name'), 'faith');
    });

    test('brings every junction along, not just notes and songs', () async {
      await seedTag('keep', 'Faith', createdAt: 100);
      await seedTag('fold', 'faith', createdAt: 200);

      // One item of each kind, tagged with the row that is about to go.
      await seedLink('sync_note_tags', 'note_id', 'l1', 'note-1', 'fold');
      await seedLink('sync_song_tags', 'song_id', 'l2', 'song-1', 'fold');
      await seedLink('sync_prayer_tags', 'prayer_id', 'l3', 'pray-1', 'fold');
      await seedLink('sync_promise_tags', 'promise_id', 'l4', 'prom-1', 'fold');

      await db.foldTagsToLowercase();

      for (final table in [
        'sync_note_tags',
        'sync_song_tags',
        'sync_prayer_tags',
        'sync_promise_tags',
      ]) {
        expect(await liveTagIdsOn(table), ['keep'],
            reason: '$table still points at the deleted tag');
      }
    });

    test('an item tagged with both spellings ends up with one, not two',
        () async {
      await seedTag('keep', 'Faith', createdAt: 100);
      await seedTag('fold', 'faith', createdAt: 200);
      await seedLink('sync_note_tags', 'note_id', 'l1', 'note-1', 'keep');
      await seedLink('sync_note_tags', 'note_id', 'l2', 'note-1', 'fold');

      await db.foldTagsToLowercase();

      expect(await liveTagIdsOn('sync_note_tags'), ['keep']);
    });

    test('lowercases names that need it and leaves distinct tags alone',
        () async {
      await seedTag('a', 'Faith', createdAt: 100);
      await seedTag('b', 'Grace', createdAt: 200);

      await db.foldTagsToLowercase();

      expect(await liveTagNames(), ['faith', 'grace']);
    });

    test('folds a non-ASCII name, which SQL LOWER() would not', () async {
      // SQLite's LOWER() only folds ASCII. Doing this in Dart is what makes
      // the stored value match what a lookup normalises to.
      await seedTag('u1', 'ГОСПОДЬ', createdAt: 100);

      await db.foldTagsToLowercase();

      expect(await liveTagNames(), ['господь']);
    });

    test('running twice changes nothing the second time', () async {
      await seedTag('keep', 'Faith', createdAt: 100);
      await seedTag('fold', 'faith', createdAt: 200);
      await seedLink('sync_note_tags', 'note_id', 'l1', 'note-1', 'fold');

      await db.foldTagsToLowercase();
      final after = await liveTagNames();
      await db.foldTagsToLowercase();

      expect(await liveTagNames(), after);
      expect(await liveTagIdsOn('sync_note_tags'), ['keep']);
    });
  });
}
