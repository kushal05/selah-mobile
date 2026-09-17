// Signing out wipes the local database, oplog included. Anything still queued
// is destroyed with it, which on a single device is the most likely way for a
// user to lose work they actually typed: write something offline, sign out,
// gone — previously with nothing said.
//
// Two things have to hold. The count the warning is built on must be accurate,
// and the clear must not leave one account's state behind for the next.

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:notify/core/database/sync_database.dart';

void main() {
  late SyncDatabase db;

  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  setUp(() {
    db = SyncDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async => db.close());

  Future<void> queueOp(String opId, {bool synced = false, int? failedAt}) {
    return db.into(db.oplog).insert(
      OplogCompanion.insert(
        opId: opId,
        entityType: 'note',
        entityId: 'note-$opId',
        operation: 'UPDATE',
        payloadJson: '{}',
        timestamp: 1,
        deviceId: 'd1',
        entityVersion: 1,
        synced: Value(synced ? 1 : 0),
        failedAt: Value(failedAt),
      ),
    );
  }

  group('what sign-out is about to destroy', () {
    test('counts only work that has not reached the server', () async {
      await queueOp('unsynced-1');
      await queueOp('unsynced-2');
      await queueOp('already-sent', synced: true);

      expect(
        await db.getPendingOpsCount(),
        2,
        reason: 'the warning must count what would actually be lost',
      );
    });

    test('a quarantined change is not counted as pending', () async {
      await queueOp('unsynced-1');
      await queueOp('given-up', failedAt: 5000);

      expect(
        await db.getPendingOpsCount(),
        1,
        reason: 'a quarantined change is already surfaced separately; counting '
            'it here would imply a sync could still send it',
      );
    });

    test('nothing queued means no warning is needed', () async {
      await queueOp('already-sent', synced: true);
      expect(await db.getPendingOpsCount(), 0);
    });
  });

  group('signing out leaves nothing behind for the next account', () {
    test('the oplog is cleared', () async {
      await queueOp('unsynced-1');
      await db.clearAllUserData();

      expect(await db.getPendingOpsCount(), 0);
    });

    test('inbound give-up records are cleared too', () async {
      await db.recordRemoteOpFailure(
        opId: 'remote-1',
        entityType: 'prayer',
        entityId: 'p1',
        error: 'disk full',
        now: 1000,
      );
      await db.deadLetterRemoteOp('remote-1');
      expect(await db.getDeadLetteredOps(), hasLength(1));

      await db.clearAllUserData();

      expect(
        await db.getDeadLetteredOps(),
        isEmpty,
        reason: 'dead-letters are keyed by the server opId, not by user — '
            'leaving them would carry one account\'s skips into the next '
            'login and grow the table for the life of the install',
      );
    });

    test('the cursor is reset so the next login pulls everything', () async {
      await db.updateSyncState(
        const SyncStateCompanion(lastRemoteCursor: Value('12345')),
      );

      await db.clearAllUserData();

      expect((await db.getSyncState()).lastRemoteCursor, isNull);
    });
  });
}
