// A list the user is looking at does not pay for merge metadata.
//
// `_toModel` decodes `field_updated_at` from JSON on every row. Drift re-emits
// a watched query on any write to the table, so editing one record re-delivers
// and re-decodes every record the user owns. Measured at 8.3ms of pure decode
// per five autosaves over a thousand rows, scaling linearly — and the app keeps
// every tab mounted in a StatefulShellRoute.indexedStack, so those streams stay
// subscribed for the life of the process once a tab has been opened.
//
// The list watches now use `_toDisplayModel`, which skips that decode. The two
// things worth pinning are that it is actually skipped, and — much more
// important — that the paths which feed merges are NOT skipped, because a
// write re-encodes whatever the model carries and an empty map there would
// erase the per-field timestamps sync depends on.

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:notify/core/database/sync_database.dart';
import 'package:notify/core/sync/repositories/person_repository.dart';

const _stamps = '{"name":1700000000000,"relation":1700000000000}';

Future<SyncDatabase> _seed() async {
  final db = SyncDatabase.forTesting(NativeDatabase.memory());
  await db.batch((b) {
    b.insertAll(db.people, [
      for (var i = 0; i < 3; i++)
        PeopleCompanion.insert(
          id: 'p$i',
          userId: 'u1',
          name: 'Person $i',
          relation: const Value('friend'),
          notes: const Value(''),
          updatedAt: i,
          createdAt: i,
          version: const Value(1),
          deleted: const Value(0),
          fieldUpdatedAt: const Value(_stamps),
        ),
    ]);
  });
  return db;
}

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  test('a list stream does not decode the merge timestamps', () async {
    final db = await _seed();
    addTearDown(db.close);
    final repo = PersonRepository(db, 'device-1');

    final people = await repo.watchAllPeople('u1').first;

    expect(people, hasLength(3));
    expect(people.every((p) => p.fieldUpdatedAt.isEmpty), isTrue,
        reason: 'the list path should use _toDisplayModel and skip the decode');
  });

  test('but a single-row read still carries them', () async {
    final db = await _seed();
    addTearDown(db.close);
    final repo = PersonRepository(db, 'device-1');

    final person = await repo.getPersonById('p1');

    // The counterpart, and the one that matters: every update re-reads the row
    // by id before writing, and _toCompanion re-encodes whatever the model
    // holds. If this ever came back empty, a save would silently wipe the
    // timestamps that field-level merge resolves conflicts with.
    expect(person, isNotNull);
    expect(person!.fieldUpdatedAt, isNotEmpty,
        reason: 'the read that feeds writes and merges must keep the decode');
    expect(person.fieldUpdatedAt['name'], 1700000000000);
  });

  test('an update round-trip preserves the timestamps on disk', () async {
    // End to end, because the two assertions above could both hold while the
    // write path still lost them somewhere in between.
    final db = await _seed();
    addTearDown(db.close);
    final repo = PersonRepository(db, 'device-1');

    await repo.updatePerson(id: 'p1', name: 'Renamed');

    final row = await (db.select(db.people)..where((t) => t.id.equals('p1')))
        .getSingle();
    expect(row.fieldUpdatedAt, isNot('{}'));
    expect(row.fieldUpdatedAt, contains('relation'),
        reason: 'a field the update did not touch must keep its timestamp');
  });
}
