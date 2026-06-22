import 'package:flutter_test/flutter_test.dart';

import 'package:notify/core/testing/test_clock.dart';

import '../core/test_app.dart';
import '../core/test_config.dart';

/// Can be called from a combined entry point or run standalone.
void offlineSyncTests() {
  final harness = TestHarness();

  setUp(() async {
    await harness.setUp();
  });

  tearDown(() async {
    await harness.tearDown();
  });

  group('Offline sync flow', () {
    test('creating a folder offline produces an oplog entry', () async {
      await harness.dbUtils.clearAll();
      expect(await harness.dbUtils.pendingOplogCount(), 0);

      TestClock.setFixed(TestConfig.baseTimestamp);

      final folderIds = await harness.seeder.seedFolders(
        1,
        userId: TestConfig.testUserId,
      );
      expect(folderIds, hasLength(1));

      final folders = await harness.db.select(harness.db.folders).get();
      final createdFolder = folders.firstWhere(
        (f) => f.id == folderIds.first,
      );
      expect(createdFolder.name, 'Folder 0');
      expect(createdFolder.deleted, 0);

      final pendingOps = await harness.dbUtils.pendingOplogs();
      expect(pendingOps, hasLength(1));

      final op = pendingOps.first;
      expect(op.entityType, 'folder');
      expect(op.entityId, folderIds.first);
      expect(op.operation, 'INSERT');
      expect(op.synced, 0);
      expect(op.timestamp, TestConfig.baseTimestamp);
    });

    test('creating multiple entities offline queues all oplogs', () async {
      await harness.dbUtils.clearAll();
      TestClock.setFixed(TestConfig.baseTimestamp);

      final folderIds = await harness.seeder.seedFolders(
        1,
        userId: TestConfig.testUserId,
      );

      TestClock.advance(1000);

      final noteIds = await harness.seeder.seedNotes(
        3,
        userId: TestConfig.testUserId,
        folderId: folderIds.first,
      );
      expect(noteIds, hasLength(3));

      final pendingCount = await harness.dbUtils.pendingOplogCount();
      expect(pendingCount, greaterThanOrEqualTo(4));

      final ops = await harness.dbUtils.pendingOplogs();
      for (final op in ops) {
        expect(op.synced, 0, reason: 'All ops should be unsynced (offline)');
      }

      final folderOp = ops.firstWhere((o) => o.entityType == 'folder');
      expect(folderOp.timestamp, TestConfig.baseTimestamp);
    });

    test('data survives database re-query (simulates restart)', () async {
      await harness.dbUtils.clearAll();
      TestClock.setFixed(TestConfig.baseTimestamp);

      final folderIds = await harness.seeder.seedFolders(
        2,
        userId: TestConfig.testUserId,
      );

      final foldersAfterRestart = await harness.db
          .select(harness.db.folders)
          .get();

      expect(
        foldersAfterRestart.where((f) => f.deleted == 0),
        hasLength(2),
        reason: 'Folders must survive across queries (simulated restart)',
      );

      final opsAfterRestart = await harness.dbUtils.pendingOplogs();
      expect(opsAfterRestart, hasLength(2));
      expect(
        opsAfterRestart.map((o) => o.entityId).toSet(),
        equals(folderIds.toSet()),
      );
    });

    test('oplog entries have correct version and entity metadata', () async {
      await harness.dbUtils.clearAll();
      TestClock.setFixed(TestConfig.baseTimestamp);

      final folderIds = await harness.seeder.seedFolders(
        1,
        userId: TestConfig.testUserId,
      );

      final ops = await harness.dbUtils.pendingOplogs();
      expect(ops, hasLength(1));

      final op = ops.first;
      expect(op.entityVersion, 1, reason: 'New entities start at version 1');
      expect(op.operation, 'INSERT');
      expect(op.entityType, 'folder');
      expect(op.entityId, folderIds.first);

      expect(op.payloadJson, isNotEmpty);
    });

    test('prayers created offline produce correct oplog entries', () async {
      await harness.dbUtils.clearAll();
      TestClock.setFixed(TestConfig.baseTimestamp);

      await harness.seeder.seedPrayers(
        2,
        userId: TestConfig.testUserId,
      );

      final ops = await harness.dbUtils.pendingOplogs();
      final prayerOps =
          ops.where((o) => o.entityType == 'prayer').toList();

      expect(prayerOps, hasLength(2));
      for (var i = 0; i < prayerOps.length; i++) {
        expect(prayerOps[i].operation, 'INSERT');
        expect(prayerOps[i].synced, 0);
        expect(prayerOps[i].entityVersion, 1);
      }
    });
  });
}

void main() => offlineSyncTests();
