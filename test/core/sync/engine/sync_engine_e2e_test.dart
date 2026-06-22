import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notify/core/database/sync_database.dart';
import 'package:notify/core/sync/config/sync_config.dart';
import 'package:notify/core/sync/engine/sync_engine.dart';
import 'package:notify/core/sync/models/note_block_model.dart';
import 'package:notify/core/sync/models/oplog_entry.dart';
import 'package:notify/core/sync/repositories/entity_access_repository.dart';
import 'package:notify/core/sync/repositories/folder_repository.dart';
import 'package:notify/core/sync/repositories/note_block_repository.dart';
import 'package:notify/core/sync/repositories/note_repository.dart';
import 'package:notify/core/sync/repositories/note_tag_repository.dart';
import 'package:notify/core/sync/repositories/prayer_log_repository.dart';
import 'package:notify/core/sync/repositories/prayer_repository.dart';
import 'package:notify/core/sync/repositories/promise_repository.dart';
import 'package:notify/core/sync/repositories/song_repository.dart';
import 'package:notify/core/sync/repositories/tag_repository.dart';
import 'package:notify/core/database/services/note_block_fts_service.dart';
import 'package:notify/core/sync/services/sync_api_client.dart';

const _userId = 'user-e2e-1';
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
  late NoteBlockRepository noteBlockRepoA;
  late PrayerRepository prayerRepoA;
  late PrayerLogRepository prayerLogRepoA;
  late TagRepository tagRepoA;
  late NoteTagRepository noteTagRepoA;
  late SongRepository songRepoA;
  late PromiseRepository promiseRepoA;

  late FolderRepository folderRepoB;
  late NoteRepository noteRepoB;
  late NoteBlockRepository noteBlockRepoB;
  late PrayerRepository prayerRepoB;
  late PrayerLogRepository prayerLogRepoB;
  late TagRepository tagRepoB;
  late NoteTagRepository noteTagRepoB;
  late SongRepository songRepoB;
  late PromiseRepository promiseRepoB;

  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  setUp(() async {
    dbA = SyncDatabase.forTesting(NativeDatabase.memory());
    dbB = SyncDatabase.forTesting(NativeDatabase.memory());
    api = _InMemorySyncApiClient();

    final ftsA = NoteBlockFtsService(dbA);
    final ftsB = NoteBlockFtsService(dbB);

    engineA = SyncEngine(
      db: dbA,
      apiClient: api,
      config: _testConfig,
      ftsService: ftsA,
    );
    engineB = SyncEngine(
      db: dbB,
      apiClient: api,
      config: _testConfig,
      ftsService: ftsB,
    );
    await engineA.initialize();
    await engineB.initialize();

    final entityAccessRepoA = EntityAccessRepository(dbA, _deviceA);
    folderRepoA = FolderRepository(dbA, _deviceA);
    noteRepoA = NoteRepository(dbA, _deviceA, ftsA, entityAccessRepoA);
    noteBlockRepoA = NoteBlockRepository(dbA, _deviceA, ftsA);
    prayerRepoA = PrayerRepository(dbA, _deviceA, entityAccessRepoA);
    prayerLogRepoA = PrayerLogRepository(dbA, _deviceA);
    tagRepoA = TagRepository(dbA, _deviceA);
    noteTagRepoA = NoteTagRepository(dbA, _deviceA);
    songRepoA = SongRepository(dbA, _deviceA, entityAccessRepoA);
    promiseRepoA = PromiseRepository(dbA, _deviceA, entityAccessRepoA);

    final entityAccessRepoB = EntityAccessRepository(dbB, _deviceB);
    folderRepoB = FolderRepository(dbB, _deviceB);
    noteRepoB = NoteRepository(dbB, _deviceB, ftsB, entityAccessRepoB);
    noteBlockRepoB = NoteBlockRepository(dbB, _deviceB, ftsB);
    prayerRepoB = PrayerRepository(dbB, _deviceB, entityAccessRepoB);
    prayerLogRepoB = PrayerLogRepository(dbB, _deviceB);
    tagRepoB = TagRepository(dbB, _deviceB);
    noteTagRepoB = NoteTagRepository(dbB, _deviceB);
    songRepoB = SongRepository(dbB, _deviceB, entityAccessRepoB);
    promiseRepoB = PromiseRepository(dbB, _deviceB, entityAccessRepoB);
  });

  tearDown(() async {
    engineA.dispose();
    engineB.dispose();
    api.dispose();
    await dbA.close();
    await dbB.close();
  });

  test('restores account-linked data on a second device', () async {
    final folder = await folderRepoA.createFolder(
      name: 'Sermons',
      userId: _userId,
      type: 'note',
    );
    final note = await noteRepoA.createNote(
      folderId: folder.id,
      userId: _userId,
      title: 'Sunday Message',
    );
    await noteBlockRepoA.createBlock(
      noteId: note.id,
      blockType: BlockType.paragraph,
      content: {'text': 'Faith and patience'},
      orderIndex: 0,
    );

    final prayer = await prayerRepoA.createPrayer(
      userId: _userId,
      title: 'Family Prayer',
      content: 'Pray daily',
    );
    await prayerLogRepoA.logPrayer(
      prayerId: prayer.id,
      userId: _userId,
      note: 'Logged from device A',
    );

    // Groups are now online-required — no local repo in tests.

    final tag = await tagRepoA.createTag(userId: _userId, name: 'faith');
    await noteTagRepoA.addTagToNote(
      noteId: note.id,
      tagId: tag.id,
      userId: _userId,
    );

    await songRepoA.createSong(
      userId: _userId,
      title: 'Amazing Grace',
      lyrics: 'Amazing grace how sweet the sound',
      chords: 'G C D',
      language: 'English',
    );

    await promiseRepoA.createPromise(
      userId: _userId,
      reference: 'Jeremiah 29:11',
      content: 'For I know the plans I have for you',
    );

    final syncA = await engineA.syncNow();
    expect(syncA.success, isTrue);
    final syncB = await engineB.syncNow();
    expect(syncB.success, isTrue);

    expect((await folderRepoB.getAllFolders(_userId)).length, 1);
    expect((await noteRepoB.getAllNotes(_userId)).length, 1);
    expect((await noteBlockRepoB.getBlocksForNote(note.id)).length, 1);
    expect((await prayerRepoB.getAllPrayers(_userId)).length, 1);
    expect((await prayerLogRepoB.getAllLogs(_userId)).length, 1);
    expect((await tagRepoB.getAllTags(_userId)).length, 1);
    expect(await noteTagRepoB.getTagIdsForNote(note.id), [tag.id]);
    expect((await songRepoB.getAllSongs(_userId)).length, 1);
    expect((await promiseRepoB.getAllPromises(_userId)).length, 1);
  });

  test('repeated sync does not duplicate data on device B', () async {
    final folder = await folderRepoA.createFolder(
      name: 'Notes',
      userId: _userId,
      type: 'note',
    );
    final note = await noteRepoA.createNote(
      folderId: folder.id,
      userId: _userId,
      title: 'Idempotency',
    );
    await noteBlockRepoA.createBlock(
      noteId: note.id,
      blockType: BlockType.paragraph,
      content: {'text': 'No duplicates'},
      orderIndex: 0,
    );

    await engineA.syncNow();
    final first = await engineB.syncNow();
    expect(first.success, isTrue);

    final countsBefore = await _activeCounts(dbB);
    final second = await engineB.syncNow();
    expect(second.success, isTrue);
    final countsAfter = await _activeCounts(dbB);

    expect(countsAfter, countsBefore);
    expect(await noteRepoB.getNoteById(note.id), isNotNull);
  });

  test('applies remote bool flags correctly during pull', () async {
    final now = DateTime.now().millisecondsSinceEpoch;
    api.addRemoteOperation(
      OplogEntry(
        opId: 'server-op-1',
        entityType: OplogEntityType.song,
        entityId: 'song-bool-1',
        operation: OplogOperation.insert,
        payload: {
          'id': 'song-bool-1',
          'userId': _userId,
          'title': 'Server Song',
          'folderId': null,
          'lyrics': 'Line',
          'chords': 'C F G',
          'scale': 'C',
          'chordLines': '[]',
          'language': 'English',
          'book': null,
          'preview': 'Line',
          'tags': '',
          'hasChords': true,
          'isFavorite': false,
          'updatedAt': now,
          'version': 1,
          'deleted': false,
          'createdAt': now,
        },
        timestamp: now,
        deviceId: 'server',
        entityVersion: 1,
      ),
      serverTimestamp: 1000,
    );

    final firstPull = await engineB.syncNow();
    expect(firstPull.success, isTrue);

    final song = await songRepoB.getSongById('song-bool-1');
    expect(song, isNotNull);
    expect(song!.hasChords, isTrue);
    expect(song.isFavorite, isFalse);
    expect(song.isDeleted, isFalse);

    api.addRemoteOperation(
      OplogEntry(
        opId: 'server-op-2',
        entityType: OplogEntityType.song,
        entityId: 'song-bool-1',
        operation: OplogOperation.delete,
        payload: {
          ...song.toJson(),
          'version': 2,
          'updatedAt': now + 1,
          'deleted': true,
        },
        timestamp: now + 1,
        deviceId: 'server',
        entityVersion: 2,
      ),
      serverTimestamp: 1001,
    );

    final secondPull = await engineB.syncNow();
    expect(secondPull.success, isTrue);

    final deletedSong = await songRepoB.getSongById('song-bool-1');
    expect(deletedSong, isNotNull);
    expect(deletedSong!.isDeleted, isTrue);
  });

  // Regression: the server normalizes isFavorite to a JSON bool, so the
  // promise apply must tolerate a bool (not cast it `as int?`, which threw a
  // TypeError and silently skipped every promise on pull).
  test('applies remote promise with bool isFavorite during pull', () async {
    final now = DateTime.now().millisecondsSinceEpoch;
    api.addRemoteOperation(
      OplogEntry(
        opId: 'server-promise-1',
        entityType: OplogEntityType.promise,
        entityId: 'promise-bool-1',
        operation: OplogOperation.insert,
        payload: {
          'id': 'promise-bool-1',
          'userId': _userId,
          'reference': 'Romans 8:28',
          'content': 'All things work together for good',
          'preview': 'All things work together for good',
          'notes': 'Encouraging',
          'category': null,
          'isFavorite': true,
          'updatedAt': now,
          'version': 1,
          'deleted': false,
          'createdAt': now,
        },
        timestamp: now,
        deviceId: 'server',
        entityVersion: 1,
      ),
      serverTimestamp: 2000,
    );

    final pull = await engineB.syncNow();
    expect(pull.success, isTrue);

    final promise = await promiseRepoB.getPromiseById('promise-bool-1');
    expect(promise, isNotNull);
    expect(promise!.isFavorite, isTrue);
    expect(promise.notes, 'Encouraging');
    expect(promise.isDeleted, isFalse);

    // A remote trash UPDATE must propagate the trashed_at timestamp so the
    // promise drops out of the active list on the receiving device.
    api.addRemoteOperation(
      OplogEntry(
        opId: 'server-promise-2',
        entityType: OplogEntityType.promise,
        entityId: 'promise-bool-1',
        operation: OplogOperation.update,
        payload: {
          ...promise.toJson(),
          'isFavorite': false,
          'trashedAt': now + 1,
          'version': 2,
          'updatedAt': now + 1,
        },
        timestamp: now + 1,
        deviceId: 'server',
        entityVersion: 2,
      ),
      serverTimestamp: 2001,
    );

    final secondPull = await engineB.syncNow();
    expect(secondPull.success, isTrue);

    expect((await promiseRepoB.getAllPromises(_userId)).length, 0);
    final trashed = await promiseRepoB.getTrashedPromises(_userId);
    expect(trashed.length, 1);
    expect(trashed.first.id, 'promise-bool-1');
    expect(trashed.first.isFavorite, isFalse);
  });
}

Future<Map<String, int>> _activeCounts(SyncDatabase db) async {
  Future<int> count(String table) async {
    final row =
        await db.customSelect('SELECT COUNT(*) AS c FROM $table WHERE deleted = 0').getSingle();
    return row.read<int>('c');
  }

  return {
    'folders': await count('folders'),
    'notes': await count('sync_notes'),
    'blocks': await count('note_blocks'),
    'prayers': await count('prayers'),
    'songs': await count('songs'),
    'groups': await count('groups'),
    'group_members': await count('group_members'),
    'tags': await count('sync_tags'),
    'note_tags': await count('sync_note_tags'),
  };
}

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

    const batchSize = 100;
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

  void addRemoteOperation(OplogEntry op, {int? serverTimestamp}) {
    final ts = serverTimestamp ?? _nextServerTs++;
    _ops.add(_StoredOp(op, ts));
    _realTimeController.add(null);
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
