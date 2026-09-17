import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show driftRuntimeOptions, Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notify/core/database/sync_database.dart';
import 'package:notify/core/sync/config/sync_config.dart';
import 'package:notify/core/sync/engine/sync_engine.dart';
import 'package:notify/core/sync/engine/sync_state_machine.dart';
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

  // Guards the page-level transaction around the pull apply loop: a malformed
  // operation must not take its page-mates down with it, and the cursor must
  // still advance past it so the pull cannot wedge.
  //
  // Note what this does *not* cover: the promise apply casts its payload while
  // building the companion, so a bad `updatedAt` throws before any INSERT is
  // issued. No partial write happens here, so no savepoint is rolled back.
  // The savepoint mechanism itself is covered separately below.
  test('a malformed operation does not discard the rest of its page', () async {
    final now = DateTime.now().millisecondsSinceEpoch;

    OplogEntry promise(String id, Map<String, dynamic> overrides) => OplogEntry(
      opId: 'server-op-$id',
      entityType: OplogEntityType.promise,
      entityId: id,
      operation: OplogOperation.insert,
      payload: {
        'id': id,
        'userId': _userId,
        'reference': 'Romans 8:28',
        'content': 'All things work together for good',
        'preview': 'All things work together for good',
        'notes': null,
        'category': null,
        'isFavorite': false,
        'updatedAt': now,
        'version': 1,
        'deleted': false,
        'createdAt': now,
        ...overrides,
      },
      timestamp: now,
      deviceId: 'server',
      entityVersion: 1,
    );

    // Good, malformed, good — all in the same pulled page.
    api.addRemoteOperation(
      promise('promise-ok-before', const {}),
      serverTimestamp: 3001,
    );
    api.addRemoteOperation(
      // updatedAt must be an int; a String makes the apply throw.
      promise('promise-broken', const {'updatedAt': 'not-a-number'}),
      serverTimestamp: 3002,
    );
    api.addRemoteOperation(
      promise('promise-ok-after', const {}),
      serverTimestamp: 3003,
    );

    final pull = await engineB.syncNow();
    expect(pull.success, isTrue);

    // Both well-formed operations survived the bad one sharing their page.
    expect(await promiseRepoB.getPromiseById('promise-ok-before'), isNotNull);
    expect(await promiseRepoB.getPromiseById('promise-ok-after'), isNotNull);

    // The malformed one was skipped rather than applied.
    expect(await promiseRepoB.getPromiseById('promise-broken'), isNull);

    // And the cursor advanced past the whole page, so the pull is not stuck.
    final state = await dbB.getSyncState();
    expect(state.lastRemoteCursor, '3003');
  });

  // The property the page-level pull transaction rests on: each
  // _applyRemoteOperation still opens its own transaction, which Drift nests
  // as `SAVEPOINT s$depth`. If a rolled-back savepoint poisoned the enclosing
  // transaction, one bad operation would still cost the whole page — so this
  // asserts a failed inner transaction rolls back only its own writes and
  // leaves the outer one able to continue.
  test('a failed nested transaction leaves its outer one usable', () async {
    final now = DateTime.now().millisecondsSinceEpoch;

    PromisesCompanion row(String id) => PromisesCompanion(
      id: Value(id),
      userId: Value(_userId),
      reference: const Value('Romans 8:28'),
      content: const Value('c'),
      preview: const Value('p'),
      notes: const Value(''),
      isFavorite: const Value(0),
      updatedAt: Value(now),
      version: const Value(1),
      deleted: const Value(0),
      createdAt: Value(now),
    );

    await dbB.transaction(() async {
      await dbB.into(dbB.promises).insert(row('before'));

      // Writes, then fails — the savepoint must undo just this write.
      try {
        await dbB.transaction(() async {
          await dbB.into(dbB.promises).insert(row('rolled-back'));
          throw StateError('boom');
        });
      } on StateError {
        // Swallowed exactly as the pull loop swallows a bad operation.
      }

      await dbB.into(dbB.promises).insert(row('after'));
    });

    Future<bool> exists(String id) async =>
        await (dbB.select(
          dbB.promises,
        )..where((p) => p.id.equals(id))).getSingleOrNull() !=
        null;

    expect(await exists('before'), isTrue, reason: 'pre-failure write kept');
    expect(await exists('rolled-back'), isFalse, reason: 'savepoint undone');
    expect(await exists('after'), isTrue, reason: 'outer txn still usable');
  });

  // The cursor must not advance past an operation that failed for a reason a
  // retry could fix. Skipping is permanent — the server never re-sends a
  // pulled operation — so a full disk or a poisoned transaction would discard
  // the user's data silently. Only an unparseable payload is safe to skip.
  test('a retryable failure leaves the cursor where it was', () async {
    final now = DateTime.now().millisecondsSinceEpoch;

    await dbB.updateSyncState(
      const SyncStateCompanion(lastRemoteCursor: Value('1000')),
    );

    api.addRemoteOperation(
      OplogEntry(
        opId: 'server-op-retryable',
        // An entity type whose apply will hit the database rather than fail
        // while parsing — then we break the database out from under it.
        entityType: OplogEntityType.promise,
        entityId: 'promise-retryable',
        operation: OplogOperation.insert,
        payload: {
          'id': 'promise-retryable',
          'userId': _userId,
          'reference': 'Romans 8:28',
          'content': 'c',
          'preview': 'p',
          'notes': null,
          'category': null,
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
      serverTimestamp: 4001,
    );

    // Drop the table so the insert raises a SqliteException — a database-level
    // failure, not a payload one.
    await dbB.customStatement('DROP TABLE promises');

    final pull = await engineB.syncNow();

    final state = await dbB.getSyncState();
    expect(
      state.lastRemoteCursor,
      '1000',
      reason: 'the cursor must not move past an operation that was not applied',
    );
    expect(pull.operationsPulled, 0);

    // Reporting this as a clean sync would reset the backoff and tell the user
    // they are up to date while the page is still on the server.
    expect(
      pull.success,
      isFalse,
      reason: 'an incomplete pull must not be reported as a successful sync',
    );

    // And it must go through the same failure handling as any other error,
    // so backoff actually engages rather than waiting for the next tick.
    expect(
      state.consecutiveFailures,
      greaterThan(0),
      reason: 'an incomplete pull must count as a failure for backoff',
    );
  });

  // The bound on the retry above: an operation that can never apply must not
  // hold the cursor forever. After enough attempts it is given up on, skipped
  // so sync can continue, and kept on record rather than vanishing.
  test('an operation that keeps failing is eventually given up on', () async {
    final now = DateTime.now().millisecondsSinceEpoch;

    api.addRemoteOperation(
      OplogEntry(
        opId: 'server-op-stuck',
        entityType: OplogEntityType.promise,
        entityId: 'promise-stuck',
        operation: OplogOperation.insert,
        payload: {
          'id': 'promise-stuck',
          'userId': _userId,
          'reference': 'Romans 8:28',
          'content': 'c',
          'preview': 'p',
          'notes': null,
          'category': null,
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
      serverTimestamp: 6001,
    );

    // A database-level failure that never resolves on its own.
    await dbB.customStatement('DROP TABLE promises');

    // Every attempt holds the cursor; the last one gives up.
    late SyncResult last;
    for (var i = 0; i < 5; i++) {
      last = await engineB.syncNow();
      expect(
        last.success,
        isFalse,
        reason: 'attempt ${i + 1} should still be reported as incomplete',
      );
    }

    final given = await dbB.getDeadLetteredOps();
    expect(given, hasLength(1));
    expect(given.single.opId, 'server-op-stuck');
    expect(given.single.attempts, greaterThanOrEqualTo(5));
    expect(
      given.single.lastError,
      isNotEmpty,
      reason: 'the reason must be kept so it can be surfaced, not just dropped',
    );

    // With it given up on, the next pull gets past it.
    final after = await engineB.syncNow();
    expect(
      after.success,
      isTrue,
      reason: 'a dead-lettered operation must stop wedging sync',
    );
    final state = await dbB.getSyncState();
    expect(state.lastRemoteCursor, '6001');
  });

  // The other half: an unparseable payload still gets skipped, so one bad
  // operation cannot wedge the pull forever.
  test('an unparseable payload is skipped and the cursor advances', () async {
    final now = DateTime.now().millisecondsSinceEpoch;

    OplogEntry promise(String id, Map<String, dynamic> overrides) => OplogEntry(
      opId: 'server-op-$id',
      entityType: OplogEntityType.promise,
      entityId: id,
      operation: OplogOperation.insert,
      payload: {
        'id': id,
        'userId': _userId,
        'reference': 'Romans 8:28',
        'content': 'c',
        'preview': 'p',
        'notes': null,
        'category': null,
        'isFavorite': false,
        'updatedAt': now,
        'version': 1,
        'deleted': false,
        'createdAt': now,
        ...overrides,
      },
      timestamp: now,
      deviceId: 'server',
      entityVersion: 1,
    );

    api.addRemoteOperation(promise('keep-me', const {}), serverTimestamp: 5001);
    api.addRemoteOperation(
      // updatedAt must be an int; a String throws a TypeError while building
      // the row, which is the one failure class that is safe to skip.
      promise('unparseable', const {'updatedAt': 'not-a-number'}),
      serverTimestamp: 5002,
    );

    final pull = await engineB.syncNow();
    expect(pull.success, isTrue);

    expect(await promiseRepoB.getPromiseById('keep-me'), isNotNull);
    expect(await promiseRepoB.getPromiseById('unparseable'), isNull);

    final state = await dbB.getSyncState();
    expect(
      state.lastRemoteCursor,
      '5002',
      reason: 'a permanently bad operation must not wedge the pull',
    );
  });

  // A server that keeps asking for a full resync used to spin the pull loop
  // forever: request, reset the cursor, request again. Sync never finished,
  // isSyncing stayed true and blocked every other sync, and the device kept
  // spending battery and data on it.
  test(
    'a server that always demands a full resync cannot loop forever',
    () async {
      api.alwaysRequireFullSync = true;
      final before = api.pullCallCount;

      final result = await engineB.syncNow().timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw StateError('pull loop did not terminate'),
      );

      expect(result.success, isFalse, reason: 'the cycle must fail, not hang');

      // One legitimate restart, then it gives up rather than asking again.
      final calls = api.pullCallCount - before;
      expect(
        calls,
        lessThanOrEqualTo(3),
        reason: 'it must stop after the bounded restart, not keep requesting',
      );

      api.alwaysRequireFullSync = false;
    },
  );

  // A version conflict must not discard the user's edit.
  //
  // It used to: VERSION_CONFLICT quarantined the operation with no record the
  // user could see, and the pull then overwrote the local copy with the
  // server's, so their typing vanished without notice.
  //
  // Now the edit is rebased — the user's changed fields are re-applied on top
  // of the version the server had — and because PromiseModel carries per-field
  // timestamps, the field the other device changed survives too.
  test('a version conflict rebases the edit instead of losing it', () async {
    final now = DateTime.now().millisecondsSinceEpoch;

    final promise = await promiseRepoB.createPromise(
      userId: _userId,
      reference: 'Romans 8:28',
      content: 'original content',
    );
    await engineB.syncNow();

    // This device edits the notes.
    await promiseRepoB.updatePromise(id: promise.id, notes: 'my local note');
    final queued = (await dbB.getUnsyncedOps()).firstWhere(
      (o) => o.entityId == promise.id,
    );
    api.rejectOpIds[queued.opId] = 'VERSION_CONFLICT';

    // Another device edited a different field, and got there first.
    api.addRemoteOperation(
      OplogEntry(
        opId: 'server-op-conflict',
        entityType: OplogEntityType.promise,
        entityId: promise.id,
        operation: OplogOperation.update,
        payload: {
          ...promise.toJson(),
          'content': 'content from the other device',
          'version': promise.version + 5,
          'updatedAt': now + 1000,
          // A real device carries a stamp for every field, not just the one
          // it changed — the others keep the time they were last written.
          // Without that, an unstamped field falls back to the record's
          // `updatedAt`, which makes the whole record look newly edited.
          'fieldUpdatedAt': {
            ...(promise.toJson()['fieldUpdatedAt'] as Map<String, dynamic>),
            'content': now + 1000,
          },
        },
        timestamp: now + 1000,
        deviceId: 'device-other',
        entityVersion: promise.version + 5,
      ),
      serverTimestamp: 9001,
    );

    // Cycle one: push conflicts, pull brings the newer version, rebase runs.
    await engineB.syncNow();
    api.rejectOpIds.remove(queued.opId);
    // Cycle two: the rebased edit pushes cleanly.
    await engineB.syncNow();

    final result = await promiseRepoB.getPromiseById(promise.id);
    expect(result, isNotNull);
    expect(
      result!.notes,
      'my local note',
      reason: "the user's own edit must survive the conflict",
    );
    expect(
      result.content,
      'content from the other device',
      reason: 'and the field the other device changed must survive with it',
    );
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
    final row = await db
        .customSelect('SELECT COUNT(*) AS c FROM $table WHERE deleted = 0')
        .getSingle();
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
  Future<List<PushOpResult>> pushOperations(List<OplogEntry> operations) async {
    final results = <PushOpResult>[];
    for (final op in operations) {
      final rejection = rejectOpIds[op.opId];
      if (rejection != null) {
        results.add(PushOpResult(opId: op.opId, errorCode: rejection));
        continue;
      }
      results.add(
        PushOpResult(opId: op.opId, serverTimestamp: await pushOperation(op)),
      );
    }
    return results;
  }

  /// opId -> error code the fake server should answer with.
  final Map<String, String> rejectOpIds = {};

  /// When true, every pull answers "start over" — the misbehaving-server case.
  bool alwaysRequireFullSync = false;
  int pullCallCount = 0;

  @override
  Future<PullResponse> pullOperations({String? cursor}) async {
    pullCallCount++;
    if (alwaysRequireFullSync) {
      return PullResponse(
        cursor: cursor ?? '0',
        operations: const [],
        batchSize: 100,
        hasMore: false,
        requiresFullSync: true,
        reason: 'test-forced',
      );
    }
    final lastTs = int.tryParse(cursor ?? '0') ?? 0;
    final sorted = _ops.where((o) => o.serverTimestamp > lastTs).toList()
      ..sort((a, b) => a.serverTimestamp.compareTo(b.serverTimestamp));

    const batchSize = 100;
    final batch = sorted.take(batchSize).toList();
    final newCursor = batch.isEmpty
        ? (cursor ?? '0')
        : batch.last.serverTimestamp.toString();

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
