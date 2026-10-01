// The indexes have to exist on the device, not merely in the source.
//
// createIndexes() held 65 CREATE INDEX statements and its only caller was a
// service locator nothing constructed, so a fresh install ran with two. Every
// query below scanned its whole table — including the unsynced-oplog read that
// every push cycle makes.

import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notify/core/database/sync_database.dart';
import 'package:sqlite3/sqlite3.dart';

/// The hot queries, and the index each one needs. Asserting on the plan rather
/// than on a name means this fails when the index stops being *used*, not just
/// when it stops being declared.
const _hotQueries = <String, (String sql, String index)>{
  'notes for a user': (
    "SELECT * FROM sync_notes WHERE user_id='u' AND deleted=0 "
        'ORDER BY updated_at DESC',
    'idx_notes_user',
  ),
  "a note's blocks": (
    "SELECT * FROM note_blocks WHERE note_id='n' AND deleted=0 "
        'ORDER BY order_index',
    'idx_blocks_order',
  ),
  'the unsynced oplog': (
    'SELECT * FROM oplog WHERE synced=0 AND failed_at IS NULL '
        'ORDER BY timestamp',
    'idx_oplog_unsynced',
  ),
  "a note's tags": (
    "SELECT * FROM sync_note_tags WHERE note_id='n' AND deleted=0",
    'idx_note_tags_note',
  ),
};

/// Queries that join, where the scan to rule out is on one side only — the
/// driving table is read in full by design (every untagged note is an answer),
/// so a blanket "no SCAN" would be wrong. What must not happen is the inner
/// side being scanned once per outer row.
const _joins = <String, (String sql, String index, String mustNotScan)>{
  // The Untagged smart collection. Without the index this read every tag link
  // for every note: 322ms at 4,000 notes, re-run on every save while live.
  'the Untagged collection': (
    'SELECT n.id FROM sync_notes n '
        'LEFT JOIN sync_note_tags t ON t.note_id = n.id AND t.deleted = 0 '
        "WHERE n.user_id = 'u' AND n.deleted = 0 AND t.id IS NULL "
        'ORDER BY n.updated_at DESC',
    'idx_note_tags_note',
    'SCAN t',
  ),
};

Future<Set<String>> indexesIn(SyncDatabase db) async {
  final rows = await db
      .customSelect("SELECT name FROM sqlite_master WHERE type='index' "
          "AND name NOT LIKE 'sqlite_%'")
      .get();
  return rows.map((r) => r.read<String>('name')).toSet();
}

Future<String> planFor(SyncDatabase db, String sql) async {
  final rows = await db.customSelect('EXPLAIN QUERY PLAN $sql').get();
  return rows.map((r) => r.read<String>('detail')).join(' | ');
}

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  test('a fresh install has them', () async {
    final db = SyncDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await db.customSelect('SELECT 1').get(); // force onCreate

    expect(await indexesIn(db), hasLength(greaterThan(60)),
        reason: 'onCreate did not create the raw-SQL indexes');
  });

  test('createIndexes can be run again over a database that has them', () async {
    // Named for what it does. It was called "an upgraded install has them" and
    // claimed in a comment to replay onUpgrade, which it never did — it calls
    // createIndexes directly. The onUpgrade wiring is the test below.
    final db = SyncDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await db.customSelect('SELECT 1').get();
    await db.customStatement('DROP INDEX IF EXISTS idx_notes_user');

    expect(await indexesIn(db), isNot(contains('idx_notes_user')));

    await db.createIndexes();

    expect(await indexesIn(db), contains('idx_notes_user'),
        reason: 'createIndexes must be idempotent and re-creatable');
  });

  test('an upgrade creates them, not just a fresh install', () async {
    // The real thing: wind user_version back one, reopen, and let drift run
    // onUpgrade. Every device that already had the app takes this path and no
    // other, so testing onCreate alone left the larger half uncovered.
    //
    // File-backed because a memory database cannot be reopened, and one step
    // back rather than to v1 because replaying the whole chain over a
    // current-schema file is the unsound probe that produced five phantom
    // failures earlier: the tables are already current, so older steps would be
    // re-adding columns that exist.
    final dir = await Directory.systemTemp.createTemp('selah_idx_');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/sync.sqlite');

    final first = SyncDatabase.forTesting(NativeDatabase(file));
    await first.customSelect('SELECT 1').get();
    final version = first.schemaVersion;
    await first.customStatement('DROP INDEX IF EXISTS idx_notes_user');
    await first.customStatement('DROP INDEX IF EXISTS idx_note_tags_note');
    expect(await indexesIn(first), isNot(contains('idx_notes_user')));
    expect(await indexesIn(first), isNot(contains('idx_note_tags_note')));
    await first.customStatement('PRAGMA user_version = ${version - 1}');
    await first.close();

    final reopened = SyncDatabase.forTesting(NativeDatabase(file));
    addTearDown(reopened.close);
    await reopened.customSelect('SELECT 1').get();

    expect(await indexesIn(reopened), contains('idx_notes_user'),
        reason: 'onUpgrade must call createIndexes; a device that already had '
            'the app never runs onCreate');
    expect(await indexesIn(reopened), contains('idx_note_tags_note'),
        reason: 'v37 has no step of its own — it relies on exactly this');
    final after = await reopened
        .customSelect('PRAGMA user_version')
        .map((r) => r.read<int>('user_version'))
        .getSingle();
    expect(after, version,
        reason: 'the migration must also land on the current version');
  });

  test('a device on the shipped schema gets the note-tags index', () async {
    // The upgrade test above winds back one step from whatever the current
    // version is, so it cannot see a version that was never bumped: without
    // the bump it simply tests 35 -> 36 and passes. This pins the version that
    // is actually on phones. Build 0.2.4+37 shipped with schema 36, so a phone
    // opening a database at 36 must run an upgrade — and leave it with the
    // index. Raise the shipped number when a build with a newer schema ships.
    const shipped = 36;

    final dir = await Directory.systemTemp.createTemp('selah_shipped_');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/sync.sqlite');

    final phone = SyncDatabase.forTesting(NativeDatabase(file));
    await phone.customSelect('SELECT 1').get();
    await phone.customStatement('DROP INDEX IF EXISTS idx_note_tags_note');
    await phone.customStatement('PRAGMA user_version = $shipped');
    await phone.close();

    final updated = SyncDatabase.forTesting(NativeDatabase(file));
    addTearDown(updated.close);
    await updated.customSelect('SELECT 1').get();

    expect(await indexesIn(updated), contains('idx_note_tags_note'),
        reason: 'opening a v$shipped database must upgrade it; if the schema '
            'version was not raised past what shipped, nothing runs');
  });

  group('joins seek on their inner side', () {
    for (final entry in _joins.entries) {
      test(entry.key, () async {
        final db = SyncDatabase.forTesting(NativeDatabase.memory());
        addTearDown(db.close);
        await db.customSelect('SELECT 1').get();

        final (sql, index, mustNotScan) = entry.value;
        final plan = await planFor(db, sql);

        expect(plan, contains('USING INDEX $index'), reason: 'plan was: $plan');
        expect(plan, isNot(contains(mustNotScan)),
            reason: 'the inner table is scanned per row: $plan');
      });
    }
  });

  group('the hot queries seek rather than scan', () {
    for (final entry in _hotQueries.entries) {
      test(entry.key, () async {
        final db = SyncDatabase.forTesting(NativeDatabase.memory());
        addTearDown(db.close);
        await db.customSelect('SELECT 1').get();

        final plan = await planFor(db, entry.value.$1);

        expect(plan, contains('USING INDEX ${entry.value.$2}'),
            reason: 'plan was: $plan');
        expect(plan, isNot(contains('SCAN ')),
            reason: 'full table scan: $plan');
      });
    }
  });

  test('every statement in createIndexes actually applies', () async {
    // A typo in a column name fails silently in a test that only counts rows
    // in sqlite_master, because CREATE INDEX IF NOT EXISTS on a bad column
    // throws rather than skipping. Running it twice proves both.
    final db = SyncDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await db.customSelect('SELECT 1').get();
    final first = await indexesIn(db);

    await db.createIndexes();

    expect(await indexesIn(db), first,
        reason: 'a second run should be a no-op');
  });

  test('sqlite3 is the one making these decisions', () {
    // Guards against the plan assertions above silently passing on a stub.
    expect(sqlite3.version.versionNumber, greaterThan(3025000));
  });
}
