import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:notify/core/database/sync_database.dart';
import 'package:notify/core/sync/repositories/local_share_code_repository.dart';

void main() {
  late SyncDatabase db;
  late LocalShareCodeRepository repo;

  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  setUp(() {
    db = SyncDatabase.forTesting(NativeDatabase.memory());
    repo = LocalShareCodeRepository(db);
  });

  tearDown(() => db.close());

  test('finds the prayer for a remembered code, ignoring case', () async {
    await repo.remember(code: 'ABCDEF123456', prayerId: 'p1', sharedPrayerId: 's1');
    expect(await repo.prayerIdFor('ABCDEF123456'), 'p1');
    expect(await repo.prayerIdFor('abcdef123456'), 'p1');
    expect(await repo.prayerIdFor('NOPE'), isNull);
  });

  test('a prayer keeps one code: re-sharing replaces the old one', () async {
    await repo.remember(code: 'OLDCODE00001', prayerId: 'p1', sharedPrayerId: 's1');
    await repo.remember(code: 'NEWCODE00002', prayerId: 'p1', sharedPrayerId: 's2');
    expect(await repo.prayerIdFor('OLDCODE00001'), isNull);
    expect(await repo.prayerIdFor('NEWCODE00002'), 'p1');
  });

  test('forgetting a prayer drops its code and leaves others alone', () async {
    await repo.remember(code: 'AAAAAAAAAAAA', prayerId: 'p1', sharedPrayerId: 's1');
    await repo.remember(code: 'BBBBBBBBBBBB', prayerId: 'p2', sharedPrayerId: 's2');
    await repo.forgetPrayer('p1');
    expect(await repo.prayerIdFor('AAAAAAAAAAAA'), isNull);
    expect(await repo.prayerIdFor('BBBBBBBBBBBB'), 'p2');
  });

  test('an empty code is never stored', () async {
    await repo.remember(code: '', prayerId: 'p1', sharedPrayerId: 's1');
    expect(await repo.prayerIdFor(''), isNull);
  });

  test('writes nothing to the oplog: share codes are local only', () async {
    await repo.remember(code: 'AAAAAAAAAAAA', prayerId: 'p1', sharedPrayerId: 's1');
    expect(await db.select(db.oplog).get(), isEmpty);
  });
}
