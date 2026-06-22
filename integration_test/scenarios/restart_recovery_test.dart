import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:notify/core/database/sync_database.dart';
import 'package:notify/core/sync/providers/sync_providers.dart';
import 'package:notify/core/testing/test_clock.dart';

import '../core/test_app.dart';
import '../core/test_config.dart';

/// Can be called from a combined entry point or run standalone.
void restartRecoveryTests() {
  final harness = TestHarness();

  setUp(() async {
    await harness.setUp();
  });

  tearDown(() async {
    await harness.tearDown();
  });

  group('Restart recovery', () {
    test('folder data persists across queries (restart simulation)', () async {
      await harness.dbUtils.clearAll();
      TestClock.setFixed(TestConfig.baseTimestamp);

      final folderIds = await harness.seeder.seedFolders(
        3,
        userId: TestConfig.testUserId,
      );

      final allFolders = await harness.db.select(harness.db.folders).get();
      final activeFolders = allFolders.where((f) => f.deleted == 0).toList();
      expect(activeFolders, hasLength(3));

      for (final id in folderIds) {
        expect(
          activeFolders.any((f) => f.id == id),
          true,
          reason: 'Folder $id should survive restart',
        );
      }
    });

    test('oplog entries persist and remain unsynced after restart', () async {
      await harness.dbUtils.clearAll();
      TestClock.setFixed(TestConfig.baseTimestamp);

      await harness.seeder.seedFolders(2, userId: TestConfig.testUserId);
      TestClock.advance(1000);
      await harness.seeder.seedPrayers(2, userId: TestConfig.testUserId);

      final ops = await harness.dbUtils.pendingOplogs();
      expect(ops.length, greaterThanOrEqualTo(4));

      for (final op in ops) {
        expect(op.synced, 0, reason: 'All ops remain unsynced after restart');
      }

      final folderOps = ops.where((o) => o.entityType == 'folder').toList();
      final prayerOps = ops.where((o) => o.entityType == 'prayer').toList();

      expect(folderOps, hasLength(2));
      expect(prayerOps, hasLength(2));

      expect(
        folderOps.first.timestamp,
        lessThan(prayerOps.first.timestamp),
        reason: 'Folder ops should have earlier timestamps',
      );
    });

    test('soft-deleted entities remain in DB with deleted=1', () async {
      await harness.dbUtils.clearAll();
      TestClock.setFixed(TestConfig.baseTimestamp);

      final folderIds = await harness.seeder.seedFolders(
        1,
        userId: TestConfig.testUserId,
      );

      TestClock.advance(1000);
      await (harness.db.update(harness.db.folders)
            ..where((f) => f.id.equals(folderIds.first)))
          .write(const FoldersCompanion(
        deleted: Value(1),
        version: Value(2),
      ));

      final allFolders = await harness.db.select(harness.db.folders).get();
      final deletedFolder = allFolders.firstWhere(
        (f) => f.id == folderIds.first,
      );
      expect(deletedFolder.deleted, 1, reason: 'Soft delete must persist');
      expect(deletedFolder.version, 2, reason: 'Version must be incremented');
    });

    test('version increments are preserved across operations', () async {
      await harness.dbUtils.clearAll();
      TestClock.setFixed(TestConfig.baseTimestamp);

      final folderIds = await harness.seeder.seedFolders(
        1,
        userId: TestConfig.testUserId,
      );

      var folder = (await harness.db.select(harness.db.folders).get())
          .firstWhere((f) => f.id == folderIds.first);
      expect(folder.version, 1);

      TestClock.advance(1000);
      final folderRepo = harness.container.read(folderRepositoryProvider);
      await folderRepo.updateFolder(
        id: folderIds.first,
        name: 'Updated Folder',
      );

      folder = (await harness.db.select(harness.db.folders).get())
          .firstWhere((f) => f.id == folderIds.first);
      expect(folder.version, 2, reason: 'Version must be incremented to 2');
      expect(folder.name, 'Updated Folder');

      final ops = await harness.dbUtils.pendingOplogs();
      final folderOps =
          ops.where((o) => o.entityId == folderIds.first).toList();
      expect(folderOps, hasLength(2));

      final insertOp = folderOps.firstWhere((o) => o.operation == 'INSERT');
      final updateOp = folderOps.firstWhere((o) => o.operation == 'UPDATE');
      expect(insertOp.entityVersion, 1);
      expect(updateOp.entityVersion, 2);
    });

    test('clearAllUserData resets everything', () async {
      TestClock.setFixed(TestConfig.baseTimestamp);
      await harness.seeder.seedFolders(3, userId: TestConfig.testUserId);
      await harness.seeder.seedPrayers(2, userId: TestConfig.testUserId);

      expect(await harness.dbUtils.pendingOplogCount(), greaterThan(0));

      await harness.dbUtils.clearAll();

      expect(await harness.dbUtils.pendingOplogCount(), 0);
      final folders = await harness.db.select(harness.db.folders).get();
      expect(folders, isEmpty);
    });
  });
}

void main() => restartRecoveryTests();
