import 'package:flutter_test/flutter_test.dart';

import 'package:notify/core/sync/engine/conflict_resolver.dart';
import 'package:notify/core/testing/test_clock.dart';

import '../core/test_app.dart';
import '../core/test_config.dart';

/// Can be called from a combined entry point or run standalone.
void conflictResolutionTests() {
  final harness = TestHarness();
  late ConflictResolver resolver;

  setUp(() async {
    await harness.setUp();
    resolver = ConflictResolver();
  });

  tearDown(() async {
    await harness.tearDown();
  });

  group('Conflict resolution rules', () {
    test('no conflict when remote version > local version', () {
      final result = resolver.resolveFolder(
        entityId: 'folder-1',
        localVersion: 1,
        localUpdatedAt: 1000,
        remoteVersion: 2,
        remoteUpdatedAt: 2000,
        remoteIsDelete: false,
        localIsDelete: false,
      );

      expect(result.hadConflict, false);
      expect(result.useRemote, true);
    });

    test('remote delete wins over local update', () {
      final result = resolver.resolveNote(
        entityId: 'note-1',
        localVersion: 2,
        localUpdatedAt: 2000,
        remoteVersion: 2,
        remoteUpdatedAt: 2000,
        remoteIsDelete: true,
        localIsDelete: false,
      );

      expect(result.hadConflict, true);
      expect(result.useRemote, true);
      expect(result.reason, contains('Delete'));
    });

    test('local delete wins over remote update', () {
      final result = resolver.resolveNote(
        entityId: 'note-1',
        localVersion: 2,
        localUpdatedAt: 2000,
        remoteVersion: 2,
        remoteUpdatedAt: 2000,
        remoteIsDelete: false,
        localIsDelete: true,
      );

      expect(result.hadConflict, true);
      expect(result.useRemote, false);
      expect(result.reason, contains('Local delete'));
    });

    test('higher updatedAt wins when versions conflict', () {
      final result = resolver.resolveFolder(
        entityId: 'folder-1',
        localVersion: 2,
        localUpdatedAt: 1000,
        remoteVersion: 2,
        remoteUpdatedAt: 2000,
        remoteIsDelete: false,
        localIsDelete: false,
      );

      expect(result.hadConflict, true);
      expect(result.useRemote, true);
      expect(result.reason, contains('higher updatedAt'));
    });

    test('local wins when local updatedAt is higher', () {
      final result = resolver.resolvePrayer(
        entityId: 'prayer-1',
        localVersion: 2,
        localUpdatedAt: 3000,
        remoteVersion: 2,
        remoteUpdatedAt: 2000,
        remoteIsDelete: false,
        localIsDelete: false,
      );

      expect(result.hadConflict, true);
      expect(result.useRemote, false);
      expect(result.reason, contains('Local'));
    });

    test('higher version wins when timestamps are equal', () {
      final result = resolver.resolveNote(
        entityId: 'note-1',
        localVersion: 2,
        localUpdatedAt: 2000,
        remoteVersion: 3,
        remoteUpdatedAt: 2000,
        remoteIsDelete: false,
        localIsDelete: false,
      );

      expect(result.hadConflict, false);
      expect(result.useRemote, true);
    });

    test('same timestamp same version: local version wins when higher', () {
      final result = resolver.resolveNote(
        entityId: 'note-1',
        localVersion: 3,
        localUpdatedAt: 2000,
        remoteVersion: 2,
        remoteUpdatedAt: 2000,
        remoteIsDelete: false,
        localIsDelete: false,
      );

      expect(result.hadConflict, true);
      expect(result.useRemote, false);
    });

    test('deterministic deviceId tiebreaker when all else equal', () {
      final result = resolver.resolveFolder(
        entityId: 'folder-1',
        localVersion: 2,
        localUpdatedAt: 2000,
        remoteVersion: 2,
        remoteUpdatedAt: 2000,
        remoteIsDelete: false,
        localIsDelete: false,
        localDeviceId: 'device-aaa',
        remoteDeviceId: 'device-zzz',
      );

      expect(result.hadConflict, true);
      expect(result.useRemote, true);
      expect(result.reason, contains('tiebreaker'));
    });

    test('deterministic tiebreaker: reversed deviceIds flip result', () {
      final result = resolver.resolveFolder(
        entityId: 'folder-1',
        localVersion: 2,
        localUpdatedAt: 2000,
        remoteVersion: 2,
        remoteUpdatedAt: 2000,
        remoteIsDelete: false,
        localIsDelete: false,
        localDeviceId: 'device-zzz',
        remoteDeviceId: 'device-aaa',
      );

      expect(result.hadConflict, true);
      expect(result.useRemote, false);
    });

    test('local default wins when no deviceIds provided', () {
      final result = resolver.resolveFolder(
        entityId: 'folder-1',
        localVersion: 2,
        localUpdatedAt: 2000,
        remoteVersion: 2,
        remoteUpdatedAt: 2000,
        remoteIsDelete: false,
        localIsDelete: false,
      );

      expect(result.hadConflict, true);
      expect(result.useRemote, false);
      expect(result.reason, contains('default'));
    });
  });

  group('Conflict resolution with DB state', () {
    test('seeded folder version matches oplog entityVersion', () async {
      await harness.dbUtils.clearAll();
      TestClock.setFixed(TestConfig.baseTimestamp);

      await harness.seeder.seedFolders(1, userId: TestConfig.testUserId);

      final ops = await harness.dbUtils.pendingOplogs();
      expect(ops, hasLength(1));
      expect(ops.first.entityVersion, 1);

      final result = resolver.resolveFolder(
        entityId: ops.first.entityId,
        localVersion: 1,
        localUpdatedAt: TestConfig.baseTimestamp,
        remoteVersion: 2,
        remoteUpdatedAt: TestConfig.baseTimestamp + 1000,
        remoteIsDelete: false,
        localIsDelete: false,
      );
      expect(result.hadConflict, false);
      expect(result.useRemote, true);
    });

    test('concurrent local+remote updates with same version conflict', () async {
      await harness.dbUtils.clearAll();
      TestClock.setFixed(TestConfig.baseTimestamp);

      await harness.seeder.seedFolders(1, userId: TestConfig.testUserId);

      final ops = await harness.dbUtils.pendingOplogs();
      final entityId = ops.first.entityId;

      final result = resolver.resolveFolder(
        entityId: entityId,
        localVersion: 1,
        localUpdatedAt: TestConfig.baseTimestamp,
        remoteVersion: 1,
        remoteUpdatedAt: TestConfig.baseTimestamp + 500,
        remoteIsDelete: false,
        localIsDelete: false,
        localDeviceId: TestConfig.testDeviceId,
        remoteDeviceId: 'remote-device-001',
      );

      expect(result.hadConflict, true);
      expect(result.useRemote, true);
    });

    test('block conflict: last writer wins (never merge)', () {
      final result = resolver.resolveBlock(
        entityId: 'block-1',
        localVersion: 3,
        localUpdatedAt: 5000,
        remoteVersion: 3,
        remoteUpdatedAt: 5000,
        remoteIsDelete: false,
        localIsDelete: false,
        localDeviceId: 'device-A',
        remoteDeviceId: 'device-B',
      );

      expect(result.hadConflict, true);
      expect(result.useRemote, true);
    });
  });
}

void main() => conflictResolutionTests();
