import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notify/core/database/sync_database.dart';
import 'package:notify/core/sync/config/sync_config.dart';
import 'package:notify/core/sync/engine/sync_engine.dart';
import 'package:notify/core/sync/models/oplog_entry.dart';
import 'package:notify/core/sync/repositories/entity_access_repository.dart';
import 'package:notify/core/sync/repositories/folder_repository.dart';
import 'package:notify/core/sync/repositories/note_repository.dart';
import 'package:notify/core/sync/repositories/prayer_log_repository.dart';
import 'package:notify/core/sync/repositories/prayer_repository.dart';
import 'package:notify/core/database/services/note_block_fts_service.dart';
import 'package:notify/core/sync/services/sync_api_client.dart';

const _userId = 'user-stress-1';
const _deviceA = 'device-a';
const _deviceB = 'device-b';
const _testConfig = SyncConfig(
  apiBaseUrl: 'http://localhost',
  wsBaseUrl: 'ws://localhost',
  periodicSyncInterval: Duration(days: 1),
);

void main() {
  late SyncDatabase dbA;
  late SyncDatabase dbB;
  late SyncEngine engineA;
  late SyncEngine engineB;
  late _InMemorySyncApiClient api;

  late FolderRepository folderRepoA;
  late NoteRepository noteRepoA;
  late PrayerRepository prayerRepoA;
  late PrayerLogRepository prayerLogRepoA;

  late FolderRepository folderRepoB;
  late NoteRepository noteRepoB;
  late PrayerRepository prayerRepoB;
  late PrayerLogRepository prayerLogRepoB;

  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  setUp(() async {
    dbA = SyncDatabase.forTesting(NativeDatabase.memory());
    dbB = SyncDatabase.forTesting(NativeDatabase.memory());
    api = _InMemorySyncApiClient();

    final ftsA = NoteBlockFtsService(dbA);
    final ftsB = NoteBlockFtsService(dbB);

    engineA = SyncEngine(db: dbA, apiClient: api, config: _testConfig, ftsService: ftsA);
    engineB = SyncEngine(db: dbB, apiClient: api, config: _testConfig, ftsService: ftsB);
    await engineA.initialize();
    await engineB.initialize();

    final entityAccessRepoA = EntityAccessRepository(dbA, _deviceA);
    folderRepoA = FolderRepository(dbA, _deviceA);
    noteRepoA = NoteRepository(dbA, _deviceA, ftsA, entityAccessRepoA);
    prayerRepoA = PrayerRepository(dbA, _deviceA, entityAccessRepoA);
    prayerLogRepoA = PrayerLogRepository(dbA, _deviceA);

    final entityAccessRepoB = EntityAccessRepository(dbB, _deviceB);
    folderRepoB = FolderRepository(dbB, _deviceB);
    noteRepoB = NoteRepository(dbB, _deviceB, ftsB, entityAccessRepoB);
    prayerRepoB = PrayerRepository(dbB, _deviceB, entityAccessRepoB);
    prayerLogRepoB = PrayerLogRepository(dbB, _deviceB);
  });

  tearDown(() async {
    engineA.dispose();
    engineB.dispose();
    api.dispose();
    await dbA.close();
    await dbB.close();
  });

  group('Stress tests', () {
    test('syncs 100 notes across 10 folders between two devices', () async {
      // Device A creates 10 folders
      final folders = <String>[];
      for (var i = 0; i < 10; i++) {
        final folder = await folderRepoA.createFolder(
          name: 'Folder $i',
          userId: _userId,
          type: 'note',
        );
        folders.add(folder.id);
      }

      // Create 100 notes across those folders
      for (var i = 0; i < 100; i++) {
        await noteRepoA.createNote(
          folderId: folders[i % 10],
          userId: _userId,
          title: 'Note $i',
        );
      }

      // Sync A → server → B
      final syncA = await engineA.syncNow();
      expect(syncA.success, isTrue);
      final syncB = await engineB.syncNow();
      expect(syncB.success, isTrue);

      // Verify device B has all data
      final bFolders = await folderRepoB.getAllFolders(_userId);
      final bNotes = await noteRepoB.getAllNotes(_userId);
      expect(bFolders.length, 10);
      expect(bNotes.length, 100);
    });

    test('syncs 50 prayers with 200 prayer logs', () async {
      // Device A creates 50 prayers
      final prayerIds = <String>[];
      for (var i = 0; i < 50; i++) {
        final prayer = await prayerRepoA.createPrayer(
          title: 'Prayer $i',
          userId: _userId,
          content: 'Content for prayer $i',
        );
        prayerIds.add(prayer.id);
      }

      // Create 200 prayer logs (4 per prayer)
      for (var i = 0; i < 200; i++) {
        await prayerLogRepoA.logPrayer(
          prayerId: prayerIds[i % 50],
          userId: _userId,
          sessionDate: '2025-01-${(i % 28 + 1).toString().padLeft(2, '0')}',
        );
      }

      // Sync
      final syncA = await engineA.syncNow();
      expect(syncA.success, isTrue);
      final syncB = await engineB.syncNow();
      expect(syncB.success, isTrue);

      // Verify
      final bPrayers = await prayerRepoB.getAllPrayers(_userId);
      final bLogs = await prayerLogRepoB.getAllLogs(_userId);
      expect(bPrayers.length, 50);
      expect(bLogs.length, 200);
    });

    test('rapid sync cycles maintain idempotency', () async {
      // Create some data on A
      final folder = await folderRepoA.createFolder(
        name: 'Rapid Test',
        userId: _userId,
        type: 'note',
      );
      for (var i = 0; i < 10; i++) {
        await noteRepoA.createNote(
          folderId: folder.id,
          userId: _userId,
          title: 'Rapid Note $i',
        );
      }

      // Run 20 rapid sync cycles
      for (var cycle = 0; cycle < 20; cycle++) {
        await engineA.syncNow();
        await engineB.syncNow();
      }

      // Verify no duplicates
      final aNotes = await noteRepoA.getAllNotes(_userId);
      final bNotes = await noteRepoB.getAllNotes(_userId);
      expect(aNotes.length, 10);
      expect(bNotes.length, 10);
    });

    test('concurrent folder moves sync correctly', () async {
      // Setup: folder with child note
      final parent = await folderRepoA.createFolder(
        name: 'Parent',
        userId: _userId,
        type: 'note',
      );
      final child = await folderRepoA.createFolder(
        name: 'Child',
        userId: _userId,
        parentId: parent.id,
        type: 'note',
      );
      final target = await folderRepoA.createFolder(
        name: 'Target',
        userId: _userId,
        type: 'note',
      );

      // Sync to B
      await engineA.syncNow();
      await engineB.syncNow();

      // Device A moves child to target
      await folderRepoA.updateFolder(id: child.id, parentId: target.id);

      // Sync both
      await engineA.syncNow();
      await engineB.syncNow();

      // Verify B sees the moved folder
      final bChild = await folderRepoB.getFolderById(child.id);
      expect(bChild, isNotNull);
      expect(bChild!.parentId, target.id);
    });
  });
}

// ==================== In-Memory Mock API ====================

class _InMemorySyncApiClient implements SyncApiClient {
  final _ops = <_StoredOp>[];
  final _realTimeController = StreamController<void>.broadcast();
  int _nextServerTs = 1;

  @override
  Future<bool> isConnected() async => true;

  @override
  Future<int> pushOperation(OplogEntry operation) async {
    final ts = _nextServerTs++;
    _ops.add(_StoredOp(operation, ts));
    _realTimeController.add(null);
    return ts;
  }

  @override
  Future<List<int>> pushOperations(List<OplogEntry> operations) async {
    final timestamps = <int>[];
    for (final op in operations) {
      timestamps.add(await pushOperation(op));
    }
    return timestamps;
  }

  @override
  Future<PullResponse> pullOperations({String? cursor}) async {
    final lastTs = int.tryParse(cursor ?? '0') ?? 0;
    final sorted = _ops
        .where((o) => o.serverTimestamp > lastTs)
        .toList()
      ..sort((a, b) => a.serverTimestamp.compareTo(b.serverTimestamp));

    const batchSize = 500;
    final batch = sorted.take(batchSize).toList();
    final newCursor =
        batch.isEmpty ? (cursor ?? '0') : batch.last.serverTimestamp.toString();

    return PullResponse(
      cursor: newCursor,
      operations: batch.map((o) => o.toRemoteEntry()).toList(),
      batchSize: batchSize,
      hasMore: sorted.length > batch.length,
    );
  }

  @override
  Stream<void> get realTimeUpdates => _realTimeController.stream;

  @override
  Future<void> connectRealTime() async {}

  @override
  Future<void> disconnectRealTime() async {}

  void dispose() {
    _realTimeController.close();
  }
}

class _StoredOp {
  final OplogEntry op;
  final int serverTimestamp;

  const _StoredOp(this.op, this.serverTimestamp);

  OplogEntry toRemoteEntry() {
    return OplogEntry(
      opId: op.opId,
      entityType: op.entityType,
      entityId: op.entityId,
      operation: op.operation,
      payload: jsonDecode(jsonEncode(op.payload)) as Map<String, dynamic>,
      timestamp: op.timestamp,
      deviceId: op.deviceId,
      entityVersion: op.entityVersion,
      synced: false,
      serverTimestamp: serverTimestamp,
    );
  }
}
