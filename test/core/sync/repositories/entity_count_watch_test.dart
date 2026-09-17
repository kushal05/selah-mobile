// The dashboard tiles used to watch the full entity lists and take `.length`,
// which decoded every row into a model on every change just to show four
// numbers. They now run a COUNT(*) instead.
//
// Two things need to hold for that swap to be safe: the count has to match
// what the list watch would have reported (same deleted/trashed filtering),
// and it has to stay reactive, because the providers went from one-shot
// FutureProviders to StreamProviders.

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notify/core/database/sync_database.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions, Value, InsertMode;
import 'package:notify/core/sync/repositories/person_repository.dart';
import 'package:notify/core/sync/repositories/prayer_repository.dart';
import 'package:notify/core/sync/repositories/entity_access_repository.dart';

const _userId = 'test-user';
const _otherUserId = 'someone-else';
const _deviceId = 'test-device';

void main() {
  late SyncDatabase db;
  late PersonRepository people;
  late PrayerRepository prayers;

  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  setUp(() async {
    db = SyncDatabase.forTesting(NativeDatabase.memory());
    people = PersonRepository(db, _deviceId);
    prayers = PrayerRepository(
      db,
      _deviceId,
      EntityAccessRepository(db, _deviceId),
    );
  });

  tearDown(() async {
    await db.close();
  });

  test('the count starts at zero and follows inserts', () async {
    final counts = people.watchPersonCount(_userId);

    expect(await counts.first, 0);

    await people.createPerson(userId: _userId, name: 'Ada');
    expect(await counts.first, 1);

    await people.createPerson(userId: _userId, name: 'Grace');
    expect(await counts.first, 2);
  });

  test('the count is scoped to the user', () async {
    await people.createPerson(userId: _userId, name: 'Ada');
    await people.createPerson(userId: _otherUserId, name: 'Not mine');

    expect(await people.watchPersonCount(_userId).first, 1);
  });

  test('a soft-deleted person drops out of the count', () async {
    final person = await people.createPerson(userId: _userId, name: 'Ada');
    expect(await people.watchPersonCount(_userId).first, 1);

    await people.deletePerson(person.id);
    expect(
      await people.watchPersonCount(_userId).first,
      0,
      reason: 'the count must apply the same deleted filter as the list watch',
    );
  });

  test('the count agrees with the list watch it replaced', () async {
    await people.createPerson(userId: _userId, name: 'Ada');
    await people.createPerson(userId: _userId, name: 'Grace');
    final removed = await people.createPerson(userId: _userId, name: 'Gone');
    await people.deletePerson(removed.id);

    final fromList = (await people.watchAllPeople(_userId).first).length;
    final fromCount = await people.watchPersonCount(_userId).first;

    expect(fromCount, fromList);
  });

  test('the stream emits again when the table changes', () async {
    final emissions = <int>[];
    final sub = people.watchPersonCount(_userId).listen(emissions.add);
    addTearDown(sub.cancel);

    await pumpEventQueue();
    await people.createPerson(userId: _userId, name: 'Ada');
    await pumpEventQueue();

    expect(
      emissions,
      containsAllInOrder(<int>[0, 1]),
      reason: 'the tile must update live, not only on first read',
    );
  });

  // The tile this replaced compared decoded models, and PrayerRepository
  // decodes an unknown status with `orElse: () => PrayerStatus.active` — so a
  // row whose status string the app does not recognise reads as Active on
  // every prayer card. A COUNT(*) matching 'active' exactly would make the
  // dashboard the one place that disagreed.
  test('an unrecognised status still counts as active', () async {
    await prayers.createPrayer(userId: _userId, title: 'Canonical');

    // What a newer server, or an older client's casing, could write.
    await db
        .into(db.prayers)
        .insert(
          PrayersCompanion(
            id: const Value('odd-status'),
            userId: const Value(_userId),
            title: const Value('Unrecognised status'),
            content: const Value(''),
            status: const Value('ACTIVE'),
            frequency: const Value('daily'),
            updatedAt: const Value(0),
            version: const Value(1),
            deleted: const Value(0),
            createdAt: const Value(0),
          ),
          mode: InsertMode.insertOrReplace,
        );

    expect(
      await prayers.watchActivePrayerCount(_userId).first,
      2,
      reason: 'the tile must agree with how the rest of the app reads status',
    );
  });

  test('answered and archived prayers are excluded', () async {
    await prayers.createPrayer(userId: _userId, title: 'Still praying');
    for (final status in ['answered', 'archived']) {
      await db
          .into(db.prayers)
          .insert(
            PrayersCompanion(
              id: Value('p-$status'),
              userId: const Value(_userId),
              title: Value(status),
              content: const Value(''),
              status: Value(status),
              frequency: const Value('daily'),
              updatedAt: const Value(0),
              version: const Value(1),
              deleted: const Value(0),
              createdAt: const Value(0),
            ),
            mode: InsertMode.insertOrReplace,
          );
    }

    expect(await prayers.watchActivePrayerCount(_userId).first, 1);
  });
}
