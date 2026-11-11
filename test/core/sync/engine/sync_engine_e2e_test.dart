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
import 'package:notify/core/sync/repositories/song_folder_repository.dart';
import 'package:notify/core/sync/repositories/song_repository.dart';
import 'package:notify/core/sync/repositories/song_tag_repository.dart';
import 'package:notify/core/sync/repositories/tag_repository.dart';
import 'package:notify/core/database/services/note_block_fts_service.dart';
import 'package:notify/core/sync/services/sync_api_client.dart';
import 'package:notify/features/bible/data/bible_highlight_repository.dart';
import 'package:notify/features/bible/data/bible_verse_note_repository.dart';
import 'package:notify/features/bible/domain/models/bible_highlight_entity.dart';

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

  group('songbook memberships (song_folder)', () {
    Future<List<String>> songbookNames(SyncDatabase db, String songId) async {
      final books = await SongFolderRepository(db, 'reader')
          .watchSongbooksForSong(songId)
          .first;
      return books.map((b) => b.name).toList();
    }

    test('a song in two songbooks arrives on another device in both', () async {
      final linksA = SongFolderRepository(dbA, _deviceA);
      final hymns = await folderRepoA.createFolder(
          name: 'Hymns', userId: _userId, type: 'song');
      final crossfire = await folderRepoA.createFolder(
          name: 'Crossfire', userId: _userId, type: 'song');
      final song = await songRepoA.createSong(
          userId: _userId, title: 'Majesty', folderId: hymns.id);
      await linksA.setFoldersForSong(
          song.id, [hymns.id, crossfire.id], _userId);

      expect((await engineA.syncNow()).success, isTrue);
      expect((await engineB.syncNow()).success, isTrue);

      // Primary first, then the rest by name.
      expect(await songbookNames(dbB, song.id), ['Hymns', 'Crossfire']);
    });

    test('removing and re-adding a link reaches the other device', () async {
      final linksA = SongFolderRepository(dbA, _deviceA);
      final hymns = await folderRepoA.createFolder(
          name: 'Hymns', userId: _userId, type: 'song');
      final ccm = await folderRepoA.createFolder(
          name: 'CCM', userId: _userId, type: 'song');
      final song = await songRepoA.createSong(
          userId: _userId, title: 'Hosanna', folderId: hymns.id);
      await linksA.setFoldersForSong(song.id, [hymns.id, ccm.id], _userId);
      await engineA.syncNow();
      await engineB.syncNow();

      await linksA.removeSongFromFolder(song.id, ccm.id);
      await engineA.syncNow();
      await engineB.syncNow();
      expect(await songbookNames(dbB, song.id), ['Hymns']);

      // Re-adding revives the same row at a higher version. Re-inserting it at
      // version 1 would lose to device B's version-2 tombstone.
      await linksA.addSongToFolder(
          songId: song.id, folderId: ccm.id, userId: _userId);
      await engineA.syncNow();
      await engineB.syncNow();
      expect(await songbookNames(dbB, song.id), ['Hymns', 'CCM']);
    });

    test('a pulled link applies trashedAt', () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      api.addRemoteOperation(
        OplogEntry(
          opId: 'server-sf-1',
          entityType: OplogEntityType.songFolder,
          entityId: 'sf-1',
          operation: OplogOperation.insert,
          payload: {
            'id': 'sf-1',
            'songId': 'song-x',
            'folderId': 'folder-x',
            'userId': _userId,
            'updatedAt': now,
            'version': 1,
            'deleted': false,
            'trashedAt': now,
            'createdAt': now,
          },
          timestamp: now,
          deviceId: 'server',
          entityVersion: 1,
        ),
        serverTimestamp: 1000,
      );

      expect((await engineB.syncNow()).success, isTrue);

      final row = await (dbB.select(dbB.syncSongFolders)
            ..where((r) => r.id.equals('sf-1')))
          .getSingle();
      expect(row.trashedAt, now);
      expect(row.deleted, 0);
    });
  });

  group('bible verse notes and highlights', () {
    late BibleVerseNoteRepository notesA;
    late BibleVerseNoteRepository notesB;
    late BibleHighlightRepository highlightsA;
    late BibleHighlightRepository highlightsB;

    setUp(() {
      notesA = BibleVerseNoteRepository(dbA, _deviceA, _userId);
      notesB = BibleVerseNoteRepository(dbB, _deviceB, _userId);
      highlightsA = BibleHighlightRepository(dbA, _deviceA, _userId);
      highlightsB = BibleHighlightRepository(dbB, _deviceB, _userId);
    });

    Future<void> syncBoth() async {
      expect((await engineA.syncNow()).success, isTrue);
      expect((await engineB.syncNow()).success, isTrue);
    }

    Future<List<String>> noteTexts(
        BibleVerseNoteRepository repo, int verse) async {
      final list = await repo
          .watchNotesForVerse(bookId: 43, chapter: 3, verse: verse)
          .first;
      return list.map((n) => n.content).toList();
    }

    test('a verse note written on one device arrives on the other', () async {
      await notesA.addNote(
          bookId: 43, chapter: 3, verse: 16, content: 'from device A');

      await syncBoth();

      expect(await noteTexts(notesB, 16), ['from device A']);
      expect(await noteTexts(notesB, 17), isEmpty);
    });

    test('editing a verse note reaches the other device', () async {
      final note = await notesA.addNote(
          bookId: 43, chapter: 3, verse: 16, content: 'first draft');
      await syncBoth();

      await notesA.updateNote(note, 'second draft');
      await syncBoth();

      expect(await noteTexts(notesB, 16), ['second draft']);
      final row = await (dbB.select(dbB.bibleVerseNotes)
            ..where((r) => r.id.equals(note.id)))
          .getSingle();
      expect(row.version, 2);
    });

    test('deleting a verse note removes it on the other device', () async {
      final note = await notesA.addNote(
          bookId: 43, chapter: 3, verse: 16, content: 'to be removed');
      await notesA.addNote(
          bookId: 43, chapter: 3, verse: 16, content: 'stays');
      await syncBoth();
      expect(await noteTexts(notesB, 16), hasLength(2));

      await notesA.deleteNote(note);
      await syncBoth();

      expect(await noteTexts(notesB, 16), ['stays']);
      final row = await (dbB.select(dbB.bibleVerseNotes)
            ..where((r) => r.id.equals(note.id)))
          .getSingle();
      expect(row.deleted, 1);
    });

    test('a verse note deleted on one device is deleted in the log payload',
        () async {
      final note = await notesA.addNote(
          bookId: 43, chapter: 3, verse: 16, content: 'x');
      await notesA.deleteNote(note);

      final ops = await (dbA.select(dbA.oplog)
            ..where((o) => o.operation.equals('DELETE')))
          .get();
      final payload = jsonDecode(ops.single.payloadJson) as Map<String, dynamic>;
      expect(payload['deleted'], 1,
          reason: 'another device must see a delete, not an update');
    });

    test('a highlight made on one device arrives on the other', () async {
      await highlightsA.createHighlight(
        bookId: 43,
        chapter: 3,
        verseStart: 16,
        verseEnd: 16,
        color: HighlightColor.green,
        note: 'an old-style note',
      );

      await syncBoth();

      final list = await highlightsB.getHighlightsForChapter(
          bookId: 43, chapter: 3);
      expect(list, hasLength(1));
      expect(list.single.color, HighlightColor.green);
      expect(list.single.note, 'an old-style note');
    });

    test('changing and removing a highlight reaches the other device',
        () async {
      final h = await highlightsA.createHighlight(
        bookId: 43,
        chapter: 3,
        verseStart: 16,
        verseEnd: 16,
        color: HighlightColor.yellow,
      );
      await syncBoth();

      await highlightsA
          .updateHighlight(h.copyWithUpdate(color: HighlightColor.pink));
      await syncBoth();
      var list =
          await highlightsB.getHighlightsForChapter(bookId: 43, chapter: 3);
      expect(list.single.color, HighlightColor.pink);

      await highlightsA.deleteHighlight(h.id);
      await syncBoth();
      list = await highlightsB.getHighlightsForChapter(bookId: 43, chapter: 3);
      expect(list, isEmpty, reason: 'removed there, so removed here');
    });

    test('a highlight delete whose payload says deleted:0 still deletes',
        () async {
      // Builds before this one wrote `deleted: 0` into a highlight's DELETE
      // operation, and those operations are still in the log.
      final h = await highlightsA.createHighlight(
        bookId: 43,
        chapter: 3,
        verseStart: 16,
        verseEnd: 16,
        color: HighlightColor.blue,
      );
      await syncBoth();
      expect(
          await highlightsB.getHighlightsForChapter(bookId: 43, chapter: 3),
          hasLength(1));

      final now = DateTime.now().millisecondsSinceEpoch + 10;
      api.addRemoteOperation(
        OplogEntry(
          opId: 'old-delete-1',
          entityType: OplogEntityType.bibleHighlight,
          entityId: h.id,
          operation: OplogOperation.delete,
          payload: {
            'id': h.id,
            'userId': _userId,
            'bookId': 43,
            'chapter': 3,
            'verseStart': 16,
            'verseEnd': 16,
            'color': 'blue',
            'note': '',
            'version': 2,
            'deleted': 0, // what the old build wrote
            'createdAt': h.createdAt,
            'updatedAt': now,
          },
          timestamp: now,
          deviceId: _deviceA,
          entityVersion: 2,
        ),
        serverTimestamp: 9000,
      );

      expect((await engineB.syncNow()).success, isTrue);

      expect(
          await highlightsB.getHighlightsForChapter(bookId: 43, chapter: 3),
          isEmpty);
    });
  });

  group('song tag weights (song_tag.weight)', () {
    Map<String, dynamic> link(String id, {int version = 1, Object? weight = 'absent'}) {
      final now = DateTime.now().millisecondsSinceEpoch;
      return {
        'id': id,
        'songId': 'song-w',
        'tagId': 'tag-w',
        'userId': _userId,
        'updatedAt': now + version,
        'version': version,
        'deleted': false,
        'trashedAt': null,
        'createdAt': now,
        if (weight != 'absent') 'weight': weight,
      };
    }

    void serve(OplogOperation op, Map<String, dynamic> payload, int ts) {
      api.addRemoteOperation(
        OplogEntry(
          opId: 'srv-w-$ts',
          entityType: OplogEntityType.songTag,
          entityId: payload['id'] as String,
          operation: op,
          payload: payload,
          timestamp: payload['updatedAt'] as int,
          deviceId: 'server',
          entityVersion: payload['version'] as int,
        ),
        serverTimestamp: ts,
      );
    }

    Future<int> weightOnB(String id) async => (await (dbB.select(dbB.syncSongTags)
              ..where((r) => r.id.equals(id)))
            .getSingle())
        .weight;

    test('a pulled insert keeps its weight; an update changes it', () async {
      serve(OplogOperation.insert, link('w1', weight: 3), 1000);
      await engineB.syncNow();
      expect(await weightOnB('w1'), 3);

      serve(OplogOperation.update, link('w1', version: 2, weight: 1), 1001);
      await engineB.syncNow();
      expect(await weightOnB('w1'), 1);
    });

    test('an older payload with no weight: 2 on insert, unchanged on update',
        () async {
      serve(OplogOperation.insert, link('w2'), 1000);
      await engineB.syncNow();
      expect(await weightOnB('w2'), 2);

      serve(OplogOperation.update, link('w2', version: 2, weight: 3), 1001);
      serve(OplogOperation.update, link('w2', version: 3), 1002);
      await engineB.syncNow();
      expect(await weightOnB('w2'), 3,
          reason: 'an update from a build without weights must not reset it');
    });

    test('an out-of-range weight is clamped', () async {
      serve(OplogOperation.insert, link('w3', weight: 9), 1000);
      serve(OplogOperation.insert, link('w4', weight: 0), 1001);
      await engineB.syncNow();
      expect(await weightOnB('w3'), 3);
      expect(await weightOnB('w4'), 1);
    });

    test('a tag removed and added back reaches the other device', () async {
      final tagsA = SongTagRepository(dbA, _deviceA);
      final song = await songRepoA.createSong(userId: _userId, title: 'S');
      final tag = await tagRepoA.createTag(userId: _userId, name: 'grace');
      await tagsA.addTagToSong(songId: song.id, tagId: tag.id, userId: _userId);
      await engineA.syncNow();
      await engineB.syncNow();
      final tagsB = SongTagRepository(dbB, _deviceB);
      expect(await tagsB.getTagIdsForSong(song.id), [tag.id]);

      await tagsA.removeTagFromSong(song.id, tag.id);
      await engineA.syncNow();
      await engineB.syncNow();
      expect(await tagsB.getTagIdsForSong(song.id), isEmpty);

      await tagsA.addTagToSong(songId: song.id, tagId: tag.id, userId: _userId);
      await engineA.syncNow();
      await engineB.syncNow();
      expect(await tagsB.getTagIdsForSong(song.id), [tag.id],
          reason: 're-adding reused the row at version 1, which loses to the '
              'version-2 tombstone everywhere else');
    });
  });

  // A trash or restore must reach every device, whichever one made it.
  group('trash and restore across devices', () {
    Future<void> syncBoth() async {
      expect((await engineA.syncNow()).success, isTrue);
      expect((await engineB.syncNow()).success, isTrue);
    }

    test('a note trashed on another device leaves the notes list, and a '
        'restore brings it back', () async {
      final note = await noteRepoA.createNote(
        folderId: 'root',
        userId: _userId,
        title: 'Moving to trash',
      );
      await syncBoth();
      expect((await noteRepoB.getAllNotes(_userId)).map((n) => n.id), [note.id]);

      await noteRepoA.trashNote(note.id);
      await syncBoth();
      expect(await noteRepoB.getAllNotes(_userId), isEmpty);
      expect((await noteRepoB.getNoteById(note.id))!.trashedAt, isNotNull);

      // The restore must state trashedAt: null explicitly.
      await noteRepoA.restoreNote(note.id);
      await syncBoth();
      expect((await noteRepoB.getAllNotes(_userId)).map((n) => n.id), [note.id]);
      expect((await noteRepoB.getNoteById(note.id))!.trashedAt, isNull);
    });

    test('a trash from the web, an update stating trashedAt, is applied',
        () async {
      final note = await noteRepoB.createNote(
        folderId: 'root',
        userId: _userId,
        title: 'Trashed in the browser',
      );
      final local = (await noteRepoB.getNoteById(note.id))!;
      final trashedAt = local.updatedAt + 1;
      api.addRemoteOperation(
        OplogEntry(
          opId: 'web-trash-1',
          entityType: OplogEntityType.note,
          entityId: note.id,
          operation: OplogOperation.update,
          payload: {
            ...local.toJson(),
            'version': local.version + 1,
            'updatedAt': trashedAt,
            'trashedAt': trashedAt,
          },
          timestamp: trashedAt,
          deviceId: 'web-browser',
          entityVersion: local.version + 1,
        ),
        serverTimestamp: 5000,
      );

      expect((await engineB.syncNow()).success, isTrue);
      expect(await noteRepoB.getAllNotes(_userId), isEmpty);
      expect((await noteRepoB.getNoteById(note.id))!.trashedAt, trashedAt);
    });

    test('an update that does not mention the trash leaves a trashed note '
        'trashed', () async {
      // An absent trashedAt key means "unchanged", not "restored".
      final note = await noteRepoB.createNote(
        folderId: 'root',
        userId: _userId,
        title: 'Trashed here',
      );
      await noteRepoB.trashNote(note.id);
      final trashed = (await noteRepoB.getNoteById(note.id))!;
      final payload = {
        ...trashed.toJson(),
        'version': trashed.version + 1,
        'updatedAt': trashed.updatedAt + 1,
      }..remove('trashedAt');
      api.addRemoteOperation(
        OplogEntry(
          opId: 'web-edit-1',
          entityType: OplogEntityType.note,
          entityId: note.id,
          operation: OplogOperation.update,
          payload: payload,
          timestamp: trashed.updatedAt + 1,
          deviceId: 'web-browser',
          entityVersion: trashed.version + 1,
        ),
        serverTimestamp: 5001,
      );

      expect((await engineB.syncNow()).success, isTrue);
      expect((await noteRepoB.getNoteById(note.id))!.trashedAt, trashed.trashedAt);
    });

    test('an ordinary edit of a trashed note or folder says nothing about '
        'the trash', () async {
      // Receivers obey a present trashedAt, so ordinary edits must omit it.
      final note = await noteRepoA.createNote(
        folderId: 'root',
        userId: _userId,
        title: 'Edited in the trash',
      );
      final trashedNote = await noteRepoA.trashNote(note.id);
      expect(
        noteRepoA.createUpdateOp(trashedNote).payload.containsKey('trashedAt'),
        isFalse,
      );
      expect(
        noteRepoA.createTrashOp(trashedNote).payload['trashedAt'],
        trashedNote.trashedAt,
      );

      final folder = await folderRepoA.createFolder(
        name: 'Edited folder',
        userId: _userId,
        type: 'note',
      );
      await folderRepoA.trashFolder(folder.id);
      final trashedFolder = (await folderRepoA.getFolderById(folder.id))!;
      expect(trashedFolder.trashedAt, isNotNull);
      expect(
        folderRepoA
            .createUpdateOp(trashedFolder)
            .payload
            .containsKey('trashedAt'),
        isFalse,
      );

      final block = await noteBlockRepoA.createBlock(
        noteId: note.id,
        blockType: BlockType.paragraph,
        content: {'text': 'Edited block'},
        orderIndex: 0,
      );
      expect(
        noteBlockRepoA
            .createUpdateOp(block.moveToTrash())
            .payload
            .containsKey('trashedAt'),
        isFalse,
      );
    });

    test('a note\'s blocks follow it into the trash and back on another '
        'device', () async {
      // Otherwise a restored note comes back elsewhere with an empty body.
      final note = await noteRepoA.createNote(
        folderId: 'root',
        userId: _userId,
        title: 'Restored with its body',
      );
      final block = await noteBlockRepoA.createBlock(
        noteId: note.id,
        blockType: BlockType.paragraph,
        content: {'text': 'Still here'},
        orderIndex: 0,
      );
      await syncBoth();

      Future<int?> blockTrashedAtOnB() async => (await (dbB.select(
        dbB.noteBlocks,
      )..where((b) => b.id.equals(block.id))).getSingle()).trashedAt;

      await noteRepoA.trashNote(note.id);
      await syncBoth();
      expect(await blockTrashedAtOnB(), isNotNull);

      await noteRepoA.restoreNote(note.id);
      await syncBoth();
      final restoreOp = api._ops
          .map((o) => o.op)
          .lastWhere((op) => op.entityId == block.id);
      expect(restoreOp.payload.containsKey('trashedAt'), isTrue);
      expect(restoreOp.payload['trashedAt'], isNull);
      expect(await blockTrashedAtOnB(), isNull);
      expect(
        (await noteBlockRepoB.getBlocksForNote(note.id)).map((b) => b.id),
        [block.id],
      );
    });

    test('a snapshot row does not undo a trash still waiting to push',
        () async {
      final note = await noteRepoB.createNote(
        folderId: 'root',
        userId: _userId,
        title: 'Trashed, not yet sent',
      );
      expect((await engineB.syncNow()).success, isTrue);

      final trashed = await noteRepoB.trashNote(note.id);
      // A retryable rejection keeps the trash queued while the pull runs.
      final queued = (await dbB.getUnsyncedOps()).firstWhere(
        (o) => o.entityId == note.id,
      );
      api.rejectOpIds[queued.opId] = 'INTERNAL_ERROR';

      api.addRemoteOperation(
        OplogEntry(
          opId: 'snapshot-row-pending',
          entityType: OplogEntityType.note,
          entityId: note.id,
          operation: OplogOperation.insert,
          payload: {
            ...trashed.toJson(),
            'version': trashed.version + 1,
            'updatedAt': trashed.updatedAt + 1,
            'trashedAt': null,
          },
          timestamp: trashed.updatedAt + 1,
          deviceId: 'server',
          entityVersion: trashed.version + 1,
        ),
        serverTimestamp: 6500,
      );

      await engineB.syncNow();
      expect(
        (await dbB.getUnsyncedOps()).any((o) => o.opId == queued.opId),
        isTrue,
        reason: 'the trash must still be waiting to push for this to test '
            'anything',
      );
      expect((await noteRepoB.getNoteById(note.id))!.trashedAt, trashed.trashedAt);
    });

    test('a snapshot row restores a note trashed here when nothing is waiting '
        'to push', () async {
      // The server only snapshots untrashed rows, so this means "restored".
      final note = await noteRepoB.createNote(
        folderId: 'root',
        userId: _userId,
        title: 'Restored elsewhere',
      );
      final trashed = await noteRepoB.trashNote(note.id);
      expect((await engineB.syncNow()).success, isTrue);

      api.addRemoteOperation(
        OplogEntry(
          opId: 'snapshot-row-1',
          entityType: OplogEntityType.note,
          entityId: note.id,
          operation: OplogOperation.insert,
          payload: {
            ...trashed.toJson(),
            'version': trashed.version + 1,
            'updatedAt': trashed.updatedAt + 1,
            'trashedAt': null,
          },
          timestamp: trashed.updatedAt + 1,
          deviceId: 'server',
          entityVersion: trashed.version + 1,
        ),
        serverTimestamp: 6000,
      );

      expect((await engineB.syncNow()).success, isTrue);
      expect((await noteRepoB.getNoteById(note.id))!.trashedAt, isNull);
    });

    test('a trash that conflicts with a newer edit keeps its trash when '
        'rebased', () async {
      final note = await noteRepoB.createNote(
        folderId: 'root',
        userId: _userId,
        title: 'Trashed while edited elsewhere',
      );
      expect((await engineB.syncNow()).success, isTrue);
      final synced = (await noteRepoB.getNoteById(note.id))!;

      final trashed = await noteRepoB.trashNote(note.id);
      final queued = (await dbB.getUnsyncedOps()).firstWhere(
        (o) => o.entityId == note.id,
      );
      api.rejectOpIds[queued.opId] = 'VERSION_CONFLICT';

      // The web renamed it, later, and says nothing about the trash.
      final later = trashed.updatedAt + 1000;
      final webPayload = {
        ...synced.toJson(),
        'title': 'Renamed on the web',
        'version': synced.version + 5,
        'updatedAt': later,
        'fieldUpdatedAt': {
          ...(synced.toJson()['fieldUpdatedAt'] as Map<String, dynamic>),
          'title': later,
        },
      }..remove('trashedAt');
      api.addRemoteOperation(
        OplogEntry(
          opId: 'web-rename-1',
          entityType: OplogEntityType.note,
          entityId: note.id,
          operation: OplogOperation.update,
          payload: webPayload,
          timestamp: later,
          deviceId: 'web-browser',
          entityVersion: synced.version + 5,
        ),
        serverTimestamp: 9100,
      );

      // Cycle one: the push conflicts and the rebase runs. Cycle two pushes it.
      await engineB.syncNow();
      api.rejectOpIds.remove(queued.opId);
      await engineB.syncNow();

      final pushed = api._ops
          .map((o) => o.op)
          .lastWhere((op) => op.entityId == note.id && op.deviceId == _deviceB);
      // The rebase rewrites the queued op in place, onto the server version.
      expect(pushed.opId, queued.opId);
      expect(pushed.entityVersion, synced.version + 6, reason: 'it was rebased');
      expect(pushed.payload['trashedAt'], trashed.trashedAt);
      expect((await noteRepoB.getNoteById(note.id))!.trashedAt, trashed.trashedAt);
    });

    test('an edit rebased onto a snapshot row does not pick up its trashedAt',
        () async {
      // The snapshot's trashedAt: null would otherwise be pushed as a restore.
      final note = await noteRepoB.createNote(
        folderId: 'root',
        userId: _userId,
        title: 'Edited here',
      );
      expect((await engineB.syncNow()).success, isTrue);
      final synced = (await noteRepoB.getNoteById(note.id))!;

      await noteRepoB.updateNote(id: note.id, title: 'Edited again');
      final queued = (await dbB.getUnsyncedOps()).firstWhere(
        (o) => o.entityId == note.id,
      );
      api.rejectOpIds[queued.opId] = 'VERSION_CONFLICT';

      api.addRemoteOperation(
        OplogEntry(
          opId: 'snapshot-row-rebase',
          entityType: OplogEntityType.note,
          entityId: note.id,
          operation: OplogOperation.insert,
          payload: {
            ...synced.toJson(),
            'version': synced.version + 5,
            'updatedAt': synced.updatedAt + 1,
            'trashedAt': null,
          },
          timestamp: synced.updatedAt + 1,
          deviceId: 'server',
          entityVersion: synced.version + 5,
        ),
        serverTimestamp: 9200,
      );

      await engineB.syncNow();
      api.rejectOpIds.remove(queued.opId);
      await engineB.syncNow();

      final pushed = api._ops
          .map((o) => o.op)
          .lastWhere((op) => op.entityId == note.id && op.deviceId == _deviceB);
      // The rebase rewrites the queued op in place, onto the server version.
      expect(pushed.opId, queued.opId);
      expect(pushed.entityVersion, synced.version + 6, reason: 'it was rebased');
      expect(pushed.payload.containsKey('trashedAt'), isFalse);
    });

    test('a folder trashed on another device is trashed here, and a restore '
        'brings it back', () async {
      final folder = await folderRepoA.createFolder(
        name: 'Old series',
        userId: _userId,
        type: 'note',
      );
      await syncBoth();
      expect((await folderRepoB.getFolderById(folder.id))!.trashedAt, isNull);

      await folderRepoA.trashFolder(folder.id);
      await syncBoth();
      expect((await folderRepoB.getFolderById(folder.id))!.trashedAt, isNotNull);

      await folderRepoA.restoreFromTrash(folder.id);
      await syncBoth();
      expect((await folderRepoB.getFolderById(folder.id))!.trashedAt, isNull);
    });
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
