// Creating a promise from a prayer must write the promise, the link and both
// oplog entries together, or not at all.

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notify/core/database/sync_database.dart';
import 'package:notify/core/sync/models/promise_prayer_link_model.dart';
import 'package:notify/core/sync/repositories/entity_access_repository.dart';
import 'package:notify/core/sync/repositories/promise_prayer_link_repository.dart';
import 'package:notify/core/sync/repositories/promise_repository.dart';

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  late SyncDatabase db;
  late PromiseRepository promises;
  late PromisePrayerLinkRepository links;

  setUp(() {
    db = SyncDatabase.forTesting(NativeDatabase.memory());
    promises = PromiseRepository(db, 'd1', EntityAccessRepository(db, 'd1'));
    links = PromisePrayerLinkRepository(db, 'd1');
    promises.linkRepository = links;
  });
  tearDown(() => db.close());

  Future<List<String>> oplogTypes() async {
    final rows = await db.select(db.oplog).get();
    return rows.map((r) => '${r.entityType}:${r.operation}').toList()..sort();
  }

  test('writes promise, link and both oplog entries', () async {
    final p = await promises.createPromiseLinkedToPrayer(
      userId: 'u1',
      prayerId: 'prayer-1',
      reference: 'Isaiah 41:10',
      content: 'Fear not',
    );

    expect((await promises.getPromiseById(p.id))?.reference, 'Isaiah 41:10');
    expect(await links.getLinkedPromiseIds('prayer-1'), [p.id]);
    expect(await oplogTypes(),
        ['promise:INSERT', 'promise_prayer_link:INSERT']);
  });

  test('a failure while linking rolls the promise back', () async {
    final bad = PromiseRepository(db, 'd1', EntityAccessRepository(db, 'd1'));
    bad.linkRepository = _FailingLinkRepo(db);

    await expectLater(
      bad.createPromiseLinkedToPrayer(
        userId: 'u1',
        prayerId: 'prayer-1',
        reference: 'Psalm 23',
        content: 'The Lord is my shepherd',
      ),
      throwsA(isA<StateError>()),
    );

    expect(await promises.getAllPromises('u1'), isEmpty);
    expect(await db.select(db.oplog).get(), isEmpty);
  });
}

class _FailingLinkRepo extends PromisePrayerLinkRepository {
  _FailingLinkRepo(SyncDatabase db) : super(db, 'd1');

  @override
  Future<PromisePrayerLinkModel> linkPromiseToPrayer({
    required String promiseId,
    required String prayerId,
    required String userId,
  }) async =>
      throw StateError('boom');
}
