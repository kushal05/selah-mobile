import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import '../../database/services/note_block_fts_service.dart';
import '../../database/sync_database.dart';
import '../../database/tables/sync_state_table.dart';
import '../config/sync_config.dart';
import '../models/oplog_entry.dart';
import '../services/sync_api_client.dart';
import 'oplog_compressor.dart';
import '../utils/sync_logger.dart';
import 'conflict_resolver.dart';
import 'field_level_merger.dart';
import 'sync_state_machine.dart';
import '../../testing/test_clock.dart';

/// Batch-decode oplog payload JSON strings off the main isolate.
/// Returns null entries for corrupt/unparseable payloads.
List<Map<String, dynamic>?> _batchDecodePayloads(List<String> payloads) {
  return payloads.map((p) {
    try {
      return jsonDecode(p) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }).toList();
}

/// Main sync engine implementation
///
/// Per spec section 5:
/// Sync Engine Responsibilities:
/// 1. Push unsynced oplog entries
/// 2. Pull remote operations
/// 3. Apply remote ops locally
/// 4. Resolve conflicts deterministically
/// 5. Recover from crashes safely
///
/// Per spec section 9:
/// Sync rules:
/// - Sync must be idempotent
/// - Sync must survive app kill
/// - Sync must not block UI
class SyncEngine {
  final SyncDatabase _db;
  final SyncApiClient _apiClient;
  final ConflictResolver _conflictResolver;
  final FieldLevelMerger _fieldMerger;
  final BackoffConfig _backoffConfig;
  final SyncConfig _config;
  final String? _localDeviceId;
  final NoteBlockFtsService _ftsService;

  SyncEngineState _state = SyncEngineState.idle;
  int _consecutiveFailures = 0;
  bool _syncRequestedWhileBusy = false;
  Timer? _retryTimer;
  Timer? _periodicTimer;

  /// Threshold after which automated sync triggers are suppressed and the
  /// engine emits a `degraded` progress event so the UI can show a banner.
  /// Manual `syncNow()`, login, and connectivity-restored events clear it.
  static const int _degradedFailureThreshold = 10;

  /// Hard cap on the failure counter so it cannot grow unbounded between
  /// successful syncs. Backoff retries already stop at `BackoffConfig.maxRetries`;
  /// this just prevents the counter itself from drifting.
  static const int _maxFailureCount = 100;

  final _progressController = StreamController<SyncProgress>.broadcast();
  final _resultController = StreamController<SyncResult>.broadcast();

  /// Stream of sync progress updates
  Stream<SyncProgress> get progressStream => _progressController.stream;

  /// Stream of sync results
  Stream<SyncResult> get resultStream => _resultController.stream;

  /// Current sync state
  SyncEngineState get state => _state;

  /// Whether sync is currently in progress
  bool get isSyncing =>
      _state == SyncEngineState.pushing ||
      _state == SyncEngineState.pulling ||
      _state == SyncEngineState.applying;

  SyncEngine({
    required SyncDatabase db,
    required SyncApiClient apiClient,
    required SyncConfig config,
    required NoteBlockFtsService ftsService,
    String? deviceId,
    ConflictResolver? conflictResolver,
    BackoffConfig? backoffConfig,
  })  : _db = db,
        _apiClient = apiClient,
        _config = config,
        _ftsService = ftsService,
        _localDeviceId = deviceId,
        _conflictResolver = conflictResolver ?? ConflictResolver(),
        _fieldMerger = FieldLevelMerger(),
        _backoffConfig = backoffConfig ?? const BackoffConfig();

  /// Initialize the sync engine
  Future<void> initialize() async {
    // Restore state from database
    final syncState = await _db.getSyncState();

    _consecutiveFailures = syncState.consecutiveFailures;

    if (syncState.syncStatus == SyncStatus.pushing ||
        syncState.syncStatus == SyncStatus.pulling) {
      // Crashed during sync - resume
      _state = SyncEngineState.idle;
      await _updateSyncStatus(SyncStatus.idle);
    }

    // Start periodic sync timer (per spec section 9: 15-30 min)
    _startPeriodicSync();
  }

  /// Start periodic sync timer
  void _startPeriodicSync() {
    _periodicTimer?.cancel();
    _periodicTimer = Timer.periodic(_config.periodicSyncInterval, (_) {
      // Skip automated ticks while degraded — manual sync, login, or
      // connectivity-restored will clear the state.
      if (_state == SyncEngineState.degraded) {
        return;
      }
      if (!isSyncing) {
        sync();
      } else {
        // Sync is busy — flag so we re-sync after the current cycle completes
        _syncRequestedWhileBusy = true;
      }
    });
  }

  /// Stop the sync engine
  void dispose() {
    _retryTimer?.cancel();
    _periodicTimer?.cancel();
    _progressController.close();
    _resultController.close();
  }

  /// Trigger a full sync (push then pull)
  ///
  /// Per spec: Push phase runs first, then pull phase
  Future<SyncResult> sync() async {
    if (isSyncing) {
      // Flag so we re-sync after the current cycle completes,
      // rather than silently dropping the request.
      _syncRequestedWhileBusy = true;
      return SyncResult.failure(
        'Sync already in progress',
        Duration.zero,
      );
    }

    final startTime = DateTime.now();
    var operationsPushed = 0;
    var operationsPulled = 0;
    var conflictsResolved = 0;

    try {
      // Debug: Log sync start info
      final pendingCount = await _db.getPendingOpsCount();
      SyncLogger.info('Sync starting: $pendingCount pending operations');

      // Check connectivity
      if (!await _apiClient.isConnected()) {
        _setState(SyncEngineState.offline);
        final pendingOps = await _db.getPendingOpsCount();
        _emitProgress(SyncProgress.offline(pendingOps));
        return SyncResult.failure(
          'Device is offline',
          DateTime.now().difference(startTime),
        );
      }

      // PUSH PHASE
      _setState(SyncEngineState.pushing);
      final pushResult = await _executePushPhase();
      operationsPushed = pushResult.operationsPushed;

      // PULL PHASE
      _setState(SyncEngineState.pulling);
      final pullResult = await _executePullPhase();
      operationsPulled = pullResult.operationsPulled;
      conflictsResolved = pullResult.conflictsResolved;

      // Success
      _consecutiveFailures = 0;
      await _updateSyncStatus(SyncStatus.idle);
      _setState(SyncEngineState.idle);

      final result = SyncResult.success(
        operationsPushed: operationsPushed,
        operationsPulled: operationsPulled,
        conflictsResolved: conflictsResolved,
        duration: DateTime.now().difference(startTime),
      );

      SyncLogger.info(
        'Sync complete: pushed=$operationsPushed, pulled=$operationsPulled, '
        'conflicts=$conflictsResolved, duration=${result.duration.inMilliseconds}ms',
      );

      _resultController.add(result);
      _emitProgress(SyncProgress.idle(await _db.getPendingOpsCount()));

      // Garbage-collect old synced oplog entries and soft-deleted records
      await _performGarbageCollection();

      // If a sync was requested while we were busy, trigger another cycle
      if (_syncRequestedWhileBusy) {
        _syncRequestedWhileBusy = false;
        // Schedule on next microtask to avoid deep recursion
        Future.microtask(() => sync()).catchError((Object e, StackTrace st) {
          SyncLogger.error('Re-sync after busy failed', e, st);
          return SyncResult.failure(e.toString(), Duration.zero);
        });
      }

      return result;
    } catch (e, st) {
      SyncLogger.error('Sync failed (attempt $_consecutiveFailures)', e, st);
      // Cap the counter so it can't grow unbounded — backoff retries already
      // stop at BackoffConfig.maxRetries; this just keeps the field sane.
      if (_consecutiveFailures < _maxFailureCount) {
        _consecutiveFailures++;
      }

      final hasCrossedDegradedThreshold =
          _consecutiveFailures >= _degradedFailureThreshold;
      final newState = hasCrossedDegradedThreshold
          ? SyncEngineState.degraded
          : SyncEngineState.error;

      await _updateSyncStatus(SyncStatus.error, error: e.toString());
      _setState(newState);

      final pendingOps = await _db.getPendingOpsCount();
      _emitProgress(hasCrossedDegradedThreshold
          ? SyncProgress.degraded(pendingOps)
          : SyncProgress.error(pendingOps));

      if (hasCrossedDegradedThreshold) {
        SyncLogger.warning(
          'Sync degraded after $_consecutiveFailures consecutive failures — '
          'automated triggers suppressed until manual sync, login, or '
          'connectivity is restored',
        );
      }

      // Don't retry on auth errors — the token refresh already failed
      // in HttpSyncClient, so retrying won't help. The user needs to
      // re-authenticate.
      final isAuthError = e is SyncApiException &&
          (e.code == 'AUTH_INVALID' ||
              e.code == 'AUTH_REQUIRED' ||
              e.code == 'TOKEN_REUSE_DETECTED' ||
              e.statusCode == 401);

      if (!isAuthError) {
        if (hasCrossedDegradedThreshold) {
          // Suppress automated retries while degraded. Drop the busy flag so
          // we don't auto-retry the moment we recover either.
          _syncRequestedWhileBusy = false;
        } else {
          // Schedule retry with backoff for non-auth errors
          if (_backoffConfig.shouldRetry(_consecutiveFailures)) {
            _scheduleRetry();
          }

          // If a sync was requested while we were busy, ensure we retry
          // even if backoff retries are exhausted (it's a new request).
          if (_syncRequestedWhileBusy) {
            _syncRequestedWhileBusy = false;
            if (!_backoffConfig.shouldRetry(_consecutiveFailures)) {
              _scheduleRetry();
            }
          }
        }
      } else {
        _syncRequestedWhileBusy = false;

        // TOKEN_REUSE_DETECTED indicates potential token theft —
        // the server has already revoked all sessions for this user.
        // Log as a security event and ensure immediate logout.
        if (e.code == 'TOKEN_REUSE_DETECTED') {
          SyncLogger.warning(
            'SECURITY: Refresh token reuse detected — possible token theft. '
            'All sessions revoked by server. Forcing immediate logout.',
          );
        } else {
          SyncLogger.warning(
            'Sync stopped due to auth error — user must re-authenticate',
          );
        }
      }

      final result = SyncResult.failure(
        e.toString(),
        DateTime.now().difference(startTime),
      );
      _resultController.add(result);
      return result;
    }
  }

  /// Execute the push phase
  ///
  /// Per spec section 5.2:
  /// Algorithm:
  /// ```
  /// SELECT * FROM oplog WHERE synced = 0 ORDER BY timestamp ASC
  /// FOR EACH batch:
  ///   send to server via batch endpoint
  ///   on success:
  ///     mark synced = 1
  ///   on partial failure:
  ///     mark successful ops synced, rethrow
  /// ```
  ///
  /// Important:
  /// - Push order MUST be preserved
  /// - Ops are fetched in bounded pages to avoid OOM on large backlogs
  /// - Batch push reduces HTTP round trips vs one-by-one
  Future<_PushResult> _executePushPhase() async {
    var operationsPushed = 0;
    final totalPending = await _db.getPendingOpsCount();

    SyncLogger.info('Push phase: $totalPending pending operations');

    if (totalPending == 0) {
      SyncLogger.info('Push phase: No operations to push');
      return _PushResult(operationsPushed: 0);
    }

    // Process in pages to avoid loading the entire oplog into memory
    final pageSize = _config.maxBatchSize;

    while (true) {
      final pendingOps = await _db.getUnsyncedOps(limit: pageSize);
      if (pendingOps.isEmpty) break;

      // Batch-decode oplog payloads off the main isolate
      final payloadStrings = pendingOps.map((op) => op.payloadJson).toList();
      final decodedPayloads = await compute(_batchDecodePayloads, payloadStrings);

      // Convert to entries, marking corrupt ones as synced so they never
      // block the push loop forever.
      final entries = <OplogEntry>[];
      for (var i = 0; i < pendingOps.length; i++) {
        final opRow = pendingOps[i];
        final payload = decodedPayloads[i];
        // payload is null on JSON parse failure; entry is null on invalid
        // entityType/operation strings — both are unrecoverable corruptions.
        final entry = payload == null
            ? null
            : _oplogDataToEntryWithPayload(opRow, payload);
        if (entry == null) {
          if (payload == null) {
            SyncLogger.error(
              'Corrupt oplog entry skipped (opId: ${opRow.opId}, '
              'entity: ${opRow.entityType}/${opRow.entityId})',
              null,
            );
          }
          await _db.markOpSyncedWithTimestamp(opRow.opId, TestClock.now());
          continue;
        }
        entries.add(entry);
      }

      if (entries.isEmpty) continue;

      // Compress consecutive UPDATE ops for the same entity within 3s
      final compressed = OplogCompressor.compress(entries);
      if (compressed.absorbedOpIds.isNotEmpty) {
        await _db.markOpsSynced(compressed.absorbedOpIds);
        operationsPushed += compressed.absorbedOpIds.length;
        SyncLogger.info(
          'Oplog compression: merged ${compressed.absorbedOpIds.length} '
          'redundant UPDATE ops',
        );
      }
      final entriesToPush = compressed.entriesToPush;
      if (entriesToPush.isEmpty) continue;

      _emitProgress(SyncProgress.pushing(
        totalPending - operationsPushed,
        totalPending,
        '${entriesToPush.length} operations',
      ));

      var pushRateLimitRetries = 0;
      while (true) {
        try {
          final timestamps = await _apiClient.pushOperations(entriesToPush);

          // Mark all as synced with their server timestamps
          for (var i = 0; i < entriesToPush.length; i++) {
            await _db.markOpSyncedWithTimestamp(entriesToPush[i].opId, timestamps[i]);
          }
          operationsPushed += entriesToPush.length;
          break; // success — exit retry loop
        } on SyncApiException catch (e) {
          // 429: pause and retry this batch (no partial results to salvage yet)
          if (e.statusCode == 429 &&
              !e.hasPartialResults &&
              pushRateLimitRetries < _maxRateLimitRetries) {
            pushRateLimitRetries++;
            await _awaitRateLimit(e, 'push');
            continue; // retry the same batch
          }

          // Mark any partially-succeeded operations as synced
          final syncedCount = e.hasPartialResults ? e.partialTimestamps.length : 0;
          if (e.hasPartialResults) {
            for (var i = 0;
                i < e.partialTimestamps.length && i < entriesToPush.length;
                i++) {
              await _db.markOpSyncedWithTimestamp(
                entriesToPush[i].opId,
                e.partialTimestamps[i],
              );
            }
            operationsPushed += syncedCount;
            SyncLogger.warning(
              'Push partially succeeded: $syncedCount/${entriesToPush.length} '
              'operations synced before failure',
            );
          }

          // Quarantine permanently failing ops instead of blocking the queue.
          // 4xx errors (except 401/429) are not retryable.
          if (_isPermanentPushError(e)) {
            for (var i = syncedCount; i < entriesToPush.length; i++) {
              await _db.markOpFailed(
                entriesToPush[i].opId,
                '${e.code}: ${e.message}',
              );
            }
            SyncLogger.warning(
              'Quarantined ${entriesToPush.length - syncedCount} ops due to '
              'permanent error: ${e.code}',
            );
            break; // Move on to next page instead of aborting
          }

          rethrow;
        }
      }
    }

    // Update last push timestamp
    await _db.updateSyncState(
      SyncStateCompanion(
        lastPushTimestamp: Value(TestClock.now()),
        pendingOpsCount: const Value(0),
      ),
    );

    return _PushResult(operationsPushed: operationsPushed);
  }

  /// Execute the pull phase
  ///
  /// Per spec section 5.3:
  /// Server returns:
  /// ```json
  /// {
  ///   "cursor": "abc123",
  ///   "operations": [ ... ]
  /// }
  /// ```
  ///
  /// Client:
  /// - Applies ops in order
  /// - Updates last_remote_cursor
  Future<_PullResult> _executePullPhase() async {
    var operationsPulled = 0;
    var conflictsResolved = 0;
    final accumulatedTypeCounts = <String, int>{};

    // Get current cursor
    final syncState = await _db.getSyncState();
    var cursor = syncState.lastRemoteCursor;

    // Pull until no more operations
    while (true) {
      _emitProgress(SyncProgress.pulling(
        counts: Map<String, int>.from(accumulatedTypeCounts),
      ));

      SyncLogger.info('Pull phase: requesting ops with cursor=$cursor');
      PullResponse response;
      var pullRateLimitRetries = 0;
      while (true) {
        try {
          response = await _apiClient.pullOperations(cursor: cursor);
          break; // success — exit retry loop
        } on SyncApiException catch (e) {
          if (e.statusCode == 429 && pullRateLimitRetries < _maxRateLimitRetries) {
            pullRateLimitRetries++;
            await _awaitRateLimit(e, 'pull');
            continue; // retry the same pull request
          }
          rethrow;
        }
      }

      // If the server signals that incremental sync is insufficient,
      // reset the cursor and restart the pull from scratch (snapshot sync).
      // Do NOT process any operations from this response.
      if (response.requiresFullSync) {
        SyncLogger.warning(
          'Server requires full sync — '
          'reason: ${response.reason ?? 'unknown'}, '
          'message: ${response.message ?? 'none'}',
        );

        // Reset cursor to null so the next pull starts from the beginning
        await _db.updateSyncState(
          const SyncStateCompanion(lastRemoteCursor: Value(null)),
        );

        // Restart the pull phase from scratch with no cursor (snapshot pull)
        cursor = null;
        continue;
      }

      SyncLogger.info(
        'Pull phase: received ${response.operations.length} ops '
        '(hasMore=${response.hasMore})',
      );

      if (response.operations.isEmpty) {
        break;
      }

      // Accumulate entity type counts across all batches
      for (final op in response.operations) {
        final key = op.entityType.toDbValue();
        accumulatedTypeCounts[key] = (accumulatedTypeCounts[key] ?? 0) + 1;
      }
      SyncLogger.info('Pull phase: accumulated entity types: $accumulatedTypeCounts');

      // Apply operations in order
      _setState(SyncEngineState.applying);
      _emitProgress(SyncProgress.applying(
        counts: Map<String, int>.from(accumulatedTypeCounts),
      ));

      var batchApplied = 0;
      var batchFailed = 0;
      final notesNeedingRebuild = <String>{};
      for (final remoteOp in response.operations) {
        try {
          final resolution = await _applyRemoteOperation(remoteOp);

          if (resolution.hadConflict) {
            conflictsResolved++;
          }

          // Track notes whose blocks changed so we can rebuild documentJson
          if (remoteOp.entityType == OplogEntityType.noteBlock) {
            final noteId = remoteOp.payload['noteId'] as String?;
            if (noteId != null) notesNeedingRebuild.add(noteId);
          }

          operationsPulled++;
          batchApplied++;
        } catch (e, stackTrace) {
          batchFailed++;
          // Log and skip malformed remote ops so the cursor can advance.
          // Without this, one bad op would block the pull phase forever.
          SyncLogger.error(
            'Failed to apply remote operation '
            '(opId: ${remoteOp.opId}, entity: '
            '${remoteOp.entityType.toDbValue()}/${remoteOp.entityId}, '
            'op: ${remoteOp.operation.toDbValue()})',
            e,
            stackTrace,
          );
        }
      }

      // Rebuild documentJson for notes whose blocks were updated.
      // The watchAllNotes stream only fires when the syncNotes row changes,
      // so block-only updates are invisible until we touch the note row.
      for (final noteId in notesNeedingRebuild) {
        try {
          await _rebuildNoteDocumentJson(noteId);
        } catch (e) {
          SyncLogger.warning('Failed to rebuild documentJson for note $noteId: $e');
        }
      }

      SyncLogger.info(
        'Pull phase batch done: applied=$batchApplied, failed=$batchFailed',
      );

      // Update cursor
      cursor = response.cursor;
      await _db.updateSyncState(
        SyncStateCompanion(lastRemoteCursor: Value(cursor)),
      );

      // Use server-provided hasMore flag to determine if there are more ops
      if (!response.hasMore) {
        break;
      }
    }

    // Update last pull timestamp
    await _db.updateSyncState(
      SyncStateCompanion(
        lastPullTimestamp: Value(TestClock.now()),
      ),
    );

    return _PullResult(
      operationsPulled: operationsPulled,
      conflictsResolved: conflictsResolved,
    );
  }

  /// Apply a remote operation locally
  ///
  /// Per spec section 7:
  /// - Detect conflicts using version/updatedAt
  /// - Resolve using deterministic rules
  /// - Never auto-merge rich text
  Future<_ApplyResult> _applyRemoteOperation(OplogEntry remoteOp) async {
    var hadConflict = false;

    await _db.transaction(() async {
      switch (remoteOp.entityType) {
        case OplogEntityType.folder:
          hadConflict = await _applyFolderOperation(remoteOp);
          break;
        case OplogEntityType.note:
          hadConflict = await _applyNoteOperation(remoteOp);
          break;
        case OplogEntityType.noteBlock:
          hadConflict = await _applyBlockOperation(remoteOp);
          break;
        case OplogEntityType.prayer:
          hadConflict = await _applyPrayerOperation(remoteOp);
          break;
        case OplogEntityType.promise:
          hadConflict = await _applyPromiseOperation(remoteOp);
          break;
        case OplogEntityType.person:
          hadConflict = await _applyPersonOperation(remoteOp);
          break;
        case OplogEntityType.song:
          hadConflict = await _applySongOperation(remoteOp);
          break;
        // New entity types - sync handlers to be implemented
        case OplogEntityType.prayerLog:
          hadConflict = await _applyPrayerLogOperation(remoteOp);
          break;
        case OplogEntityType.userProfile:
          hadConflict = await _applyUserProfileOperation(remoteOp);
          break;
        case OplogEntityType.group:
          hadConflict = await _applyGroupOperation(remoteOp);
          break;
        // Social entities are online-required — skip local sync
        case OplogEntityType.friendship:
        case OplogEntityType.friendRequest:
        case OplogEntityType.blockedUser:
        case OplogEntityType.sharedPrayer:
        case OplogEntityType.prayerCollaborator:
        case OplogEntityType.groupMember:
        case OplogEntityType.groupPrayer:
        case OplogEntityType.groupAnnouncement:
          break;
        case OplogEntityType.preacher:
          hadConflict = await _applyPreacherOperation(remoteOp);
          break;
        case OplogEntityType.tag:
          hadConflict = await _applyTagOperation(remoteOp);
          break;
        case OplogEntityType.noteTag:
          hadConflict = await _applyNoteTagOperation(remoteOp);
          break;
        case OplogEntityType.prayerUpdate:
          hadConflict = await _applyPrayerUpdateOperation(remoteOp);
          break;
        case OplogEntityType.promiseCondition:
          hadConflict = await _applyPromiseConditionOperation(remoteOp);
          break;
        case OplogEntityType.promiseTag:
          hadConflict = await _applyPromiseTagOperation(remoteOp);
          break;
        case OplogEntityType.prayerTag:
          hadConflict = await _applyPrayerTagOperation(remoteOp);
          break;
        case OplogEntityType.prayerPerson:
          hadConflict = await _applyPrayerPersonOperation(remoteOp);
          break;
        case OplogEntityType.songTag:
          hadConflict = await _applySongTagOperation(remoteOp);
          break;
        case OplogEntityType.pendingGroupMember:
          break;
        case OplogEntityType.promisePrayerLink:
          hadConflict = await _applyPromisePrayerLinkOperation(remoteOp);
          break;
        case OplogEntityType.entityAccess:
          hadConflict = await _applyEntityAccessOperation(remoteOp);
          break;
        case OplogEntityType.feedbackThread:
          hadConflict = await _applyFeedbackThreadOperation(remoteOp);
          break;
        case OplogEntityType.feedbackMessage:
          hadConflict = await _applyFeedbackMessageOperation(remoteOp);
          break;
        case OplogEntityType.feedbackAttachment:
          hadConflict = await _applyFeedbackAttachmentOperation(remoteOp);
          break;
        case OplogEntityType.bibleReferenceHistory:
          hadConflict = await _applyBibleReferenceHistoryOperation(remoteOp);
          break;
        // Flutter-only pending Worker support — no remote sync handler yet
        case OplogEntityType.bibleHighlight:
          break;
        case OplogEntityType.habitLog:
          hadConflict = await _applyHabitLogOperation(remoteOp);
          break;
      }
    });

    return _ApplyResult(hadConflict: hadConflict);
  }

  /// Apply a folder operation from remote
  Future<bool> _applyFolderOperation(OplogEntry remoteOp) async {
    final localFolder = await (_db.select(_db.folders)
          ..where((f) => f.id.equals(remoteOp.entityId)))
        .getSingleOrNull();

    if (localFolder == null) {
      // No local version - apply directly
      if (remoteOp.operation != OplogOperation.delete) {
        await _db.into(_db.folders).insert(
              FoldersCompanion(
                id: Value(remoteOp.payload['id'] as String),
                parentId: Value(remoteOp.payload['parentId'] as String?),
                name: Value(remoteOp.payload['name'] as String),
                type: Value(remoteOp.payload['type'] as String? ?? 'note'),
                visibility: Value(remoteOp.payload['visibility'] as String? ?? 'personal'),
                groupId: Value(remoteOp.payload['groupId'] as String?),
                userId: Value(remoteOp.payload['userId'] as String),
                updatedAt: Value(remoteOp.payload['updatedAt'] as int),
                version: Value(remoteOp.payload['version'] as int),
                deleted: Value(_asIntFlag(remoteOp.payload['deleted'])),
                createdAt: Value(remoteOp.payload['createdAt'] as int),
              ),
              mode: InsertMode.insertOrReplace,
            );
      }
      return false;
    }

    // Check for conflict
    final resolution = _conflictResolver.resolveFolder(
      entityId: remoteOp.entityId,
      localVersion: localFolder.version,
      localUpdatedAt: localFolder.updatedAt,
      remoteVersion: remoteOp.entityVersion,
      remoteUpdatedAt: remoteOp.payload['updatedAt'] as int,
      remoteIsDelete: remoteOp.operation == OplogOperation.delete,
      localIsDelete: localFolder.deleted == 1,
      localDeviceId: _localDeviceId,
      remoteDeviceId: remoteOp.deviceId,
    );

    if (resolution.useRemote) {
      // Apply remote version
      await (_db.update(_db.folders)
            ..where((f) => f.id.equals(remoteOp.entityId)))
          .write(
        FoldersCompanion(
          parentId: Value(remoteOp.payload['parentId'] as String?),
          name: Value(remoteOp.payload['name'] as String),
          type: Value(remoteOp.payload['type'] as String? ?? 'note'),
          visibility: Value(remoteOp.payload['visibility'] as String? ?? 'personal'),
          groupId: Value(remoteOp.payload['groupId'] as String?),
          updatedAt: Value(remoteOp.payload['updatedAt'] as int),
          version: Value(remoteOp.payload['version'] as int),
          deleted: Value(_asIntFlag(remoteOp.payload['deleted'])),
        ),
      );
    }

    return resolution.hadConflict;
  }

  /// Apply a note operation from remote using field-level merge.
  Future<bool> _applyNoteOperation(OplogEntry remoteOp) async {
    final localNote = await (_db.select(_db.syncNotes)
          ..where((n) => n.id.equals(remoteOp.entityId)))
        .getSingleOrNull();

    if (localNote == null) {
      if (remoteOp.operation != OplogOperation.delete) {
        await _db.into(_db.syncNotes).insert(
              SyncNotesCompanion(
                id: Value(remoteOp.payload['id'] as String),
                folderId: Value((remoteOp.payload['folderId'] as String?) ?? 'root'),
                userId: Value(remoteOp.payload['userId'] as String),
                title: Value(remoteOp.payload['title'] as String),
                updatedAt: Value(remoteOp.payload['updatedAt'] as int),
                version: Value(remoteOp.payload['version'] as int),
                deleted: Value(_asIntFlag(remoteOp.payload['deleted'])),
                createdAt: Value(remoteOp.payload['createdAt'] as int),
                preacherId: Value(remoteOp.payload['preacherId'] as String?),
                noteDate: Value(remoteOp.payload['noteDate'] as int?),
                trashedAt: Value(remoteOp.payload['trashedAt'] as int?),
                fieldUpdatedAt: Value(
                  jsonEncode(_parseFieldTimestamps(remoteOp.payload['fieldUpdatedAt'])),
                ),
                documentJson: Value(remoteOp.payload['documentJson'] as String?),
              ),
              mode: InsertMode.insertOrReplace,
            );
      }
      return false;
    }

    // Delete always wins
    final remoteIsDelete = remoteOp.operation == OplogOperation.delete;
    final localIsDelete = localNote.deleted == 1;
    if (remoteIsDelete || localIsDelete) {
      if (remoteIsDelete) {
        await (_db.update(_db.syncNotes)
              ..where((n) => n.id.equals(remoteOp.entityId)))
            .write(SyncNotesCompanion(
          deleted: const Value(1),
          updatedAt: Value(remoteOp.payload['updatedAt'] as int),
          version: Value(remoteOp.payload['version'] as int),
        ));
      }
      return true;
    }

    // Field-level merge
    const mergeableFields = ['title', 'folderId', 'preacherId', 'noteDate', 'documentJson'];

    final mergeResult = _fieldMerger.merge(
      localFields: {
        'title': localNote.title,
        'folderId': localNote.folderId,
        'preacherId': localNote.preacherId,
        'noteDate': localNote.noteDate,
        'documentJson': localNote.documentJson,
      },
      localFieldTimestamps: _parseFieldTimestamps(localNote.fieldUpdatedAt),
      localUpdatedAt: localNote.updatedAt,
      localVersion: localNote.version,
      remoteFields: {
        'title': remoteOp.payload['title'],
        'folderId': remoteOp.payload['folderId'],
        'preacherId': remoteOp.payload['preacherId'],
        'noteDate': remoteOp.payload['noteDate'],
        'documentJson': remoteOp.payload['documentJson'],
      },
      remoteFieldTimestamps: _parseFieldTimestamps(
        remoteOp.payload['fieldUpdatedAt'],
      ),
      remoteUpdatedAt: remoteOp.payload['updatedAt'] as int,
      remoteVersion: remoteOp.payload['version'] as int,
      localDeviceId: _localDeviceId ?? '',
      remoteDeviceId: remoteOp.deviceId,
      mergeableFieldNames: mergeableFields,
    );

    await (_db.update(_db.syncNotes)
          ..where((n) => n.id.equals(remoteOp.entityId)))
        .write(SyncNotesCompanion(
      title: Value(mergeResult.mergedFields['title'] as String),
      folderId: Value((mergeResult.mergedFields['folderId'] as String?) ?? 'root'),
      preacherId: Value(mergeResult.mergedFields['preacherId'] as String?),
      noteDate: Value(mergeResult.mergedFields['noteDate'] as int?),
      documentJson: Value(mergeResult.mergedFields['documentJson'] as String?),
      updatedAt: Value(mergeResult.mergedUpdatedAt),
      version: Value(mergeResult.mergedVersion),
      fieldUpdatedAt: Value(jsonEncode(mergeResult.mergedFieldTimestamps)),
    ));

    return true;
  }

  /// Apply a block operation from remote
  ///
  /// Per spec section 7:
  /// - Block conflict: Last writer wins
  /// - Never auto-merge rich text
  Future<bool> _applyBlockOperation(OplogEntry remoteOp) async {
    final localBlock = await (_db.select(_db.noteBlocks)
          ..where((b) => b.id.equals(remoteOp.entityId)))
        .getSingleOrNull();

    if (localBlock == null) {
      if (remoteOp.operation != OplogOperation.delete) {
        final contentJson = remoteOp.payload['content'];
        final contentStr = contentJson is String
            ? contentJson
            : jsonEncode(contentJson);
        final isDeleted = _asIntFlag(remoteOp.payload['deleted']) == 1;

        await _db.into(_db.noteBlocks).insert(
              NoteBlocksCompanion(
                id: Value(remoteOp.payload['id'] as String),
                noteId: Value(remoteOp.payload['noteId'] as String),
                blockType: Value(remoteOp.payload['blockType'] as String),
                contentJson: Value(contentStr),
                orderIndex: Value(remoteOp.payload['orderIndex'] as int),
                updatedAt: Value(remoteOp.payload['updatedAt'] as int),
                version: Value(remoteOp.payload['version'] as int),
                deleted: Value(_asIntFlag(remoteOp.payload['deleted'])),
                createdAt: Value(remoteOp.payload['createdAt'] as int),
                section: Value(remoteOp.payload['section'] as String? ?? 'main'),
              ),
              mode: InsertMode.insertOrReplace,
            );

        if (!isDeleted) {
          await _ftsService.insertIntoFts(
            blockId: remoteOp.payload['id'] as String,
            noteId: remoteOp.payload['noteId'] as String,
            contentJson: contentStr,
          );
        }
      }
      return false;
    }

    final resolution = _conflictResolver.resolveBlock(
      entityId: remoteOp.entityId,
      localVersion: localBlock.version,
      localUpdatedAt: localBlock.updatedAt,
      remoteVersion: remoteOp.entityVersion,
      remoteUpdatedAt: remoteOp.payload['updatedAt'] as int,
      remoteIsDelete: remoteOp.operation == OplogOperation.delete,
      localIsDelete: localBlock.deleted == 1,
      localDeviceId: _localDeviceId,
      remoteDeviceId: remoteOp.deviceId,
    );

    if (resolution.useRemote) {
      final contentJson = remoteOp.payload['content'];
      final contentStr = contentJson is String
          ? contentJson
          : jsonEncode(contentJson);
      final isDeleted = _asIntFlag(remoteOp.payload['deleted']) == 1;

      // Remove old FTS entry before overwriting
      if (localBlock.deleted == 0) {
        await _ftsService.removeFromFts(blockId: remoteOp.entityId);
      }

      await (_db.update(_db.noteBlocks)
            ..where((b) => b.id.equals(remoteOp.entityId)))
          .write(
        NoteBlocksCompanion(
          blockType: Value(remoteOp.payload['blockType'] as String),
          contentJson: Value(contentStr),
          orderIndex: Value(remoteOp.payload['orderIndex'] as int),
          updatedAt: Value(remoteOp.payload['updatedAt'] as int),
          version: Value(remoteOp.payload['version'] as int),
          deleted: Value(_asIntFlag(remoteOp.payload['deleted'])),
          section: Value(remoteOp.payload['section'] as String? ?? 'main'),
        ),
      );

      // Insert new FTS entry if not deleted
      if (!isDeleted) {
        await _ftsService.insertIntoFts(
          blockId: remoteOp.entityId,
          noteId: remoteOp.payload['noteId'] as String,
          contentJson: contentStr,
        );
      }
    }

    return resolution.hadConflict;
  }

  /// Rebuild the documentJson snapshot for a note after its blocks change.
  ///
  /// The watchAllNotes stream only fires when the syncNotes row is updated.
  /// When block operations arrive without a corresponding note operation,
  /// the stream never re-emits unless we write to the note row.
  Future<void> _rebuildNoteDocumentJson(String noteId) async {
    final blocks = await (_db.select(_db.noteBlocks)
          ..where((b) => b.noteId.equals(noteId) & b.deleted.equals(0))
          ..orderBy([
            (b) => OrderingTerm.asc(b.section),
            (b) => OrderingTerm.asc(b.orderIndex),
          ]))
        .get();

    final blockJsonList = blocks.map((b) {
      Map<String, dynamic> content;
      try {
        content = jsonDecode(b.contentJson) as Map<String, dynamic>;
      } catch (_) {
        content = {};
      }
      return {
        'id': b.id,
        'noteId': b.noteId,
        'blockType': b.blockType,
        'content': content,
        'orderIndex': b.orderIndex,
        'updatedAt': b.updatedAt,
        'version': b.version,
        'deleted': b.deleted,
        'createdAt': b.createdAt,
        'section': b.section,
      };
    }).toList();

    final documentJson = blocks.isEmpty ? null : jsonEncode(blockJsonList);

    await (_db.update(_db.syncNotes)
          ..where((n) => n.id.equals(noteId)))
        .write(SyncNotesCompanion(documentJson: Value(documentJson)));
  }

  /// Apply a prayer operation from remote
  /// Apply a prayer operation from remote using field-level merge.
  Future<bool> _applyPrayerOperation(OplogEntry remoteOp) async {
    final localPrayer = await (_db.select(_db.prayers)
          ..where((p) => p.id.equals(remoteOp.entityId)))
        .getSingleOrNull();

    if (localPrayer == null) {
      if (remoteOp.operation != OplogOperation.delete) {
        await _db.into(_db.prayers).insert(
              PrayersCompanion(
                id: Value(remoteOp.payload['id'] as String),
                userId: Value(remoteOp.payload['userId'] as String),
                title: Value(remoteOp.payload['title'] as String),
                content: Value(remoteOp.payload['content'] as String? ?? ''),
                frequency: Value(remoteOp.payload['frequency'] as String? ?? 'daily'),
                status: Value(remoteOp.payload['status'] as String? ?? 'active'),
                category: Value(remoteOp.payload['category'] as String?),
                reminderAt: Value(remoteOp.payload['reminderAt'] as int?),
                answeredAt: Value(remoteOp.payload['answeredAt'] as int?),
                updatedAt: Value(remoteOp.payload['updatedAt'] as int),
                version: Value(remoteOp.payload['version'] as int),
                deleted: Value(_asIntFlag(remoteOp.payload['deleted'])),
                createdAt: Value(remoteOp.payload['createdAt'] as int),
                fieldUpdatedAt: Value(
                  jsonEncode(_parseFieldTimestamps(remoteOp.payload['fieldUpdatedAt'])),
                ),
              ),
              mode: InsertMode.insertOrReplace,
            );
      }
      return false;
    }

    // Delete always wins
    final remoteIsDelete = remoteOp.operation == OplogOperation.delete;
    final localIsDelete = localPrayer.deleted == 1;
    if (remoteIsDelete || localIsDelete) {
      if (remoteIsDelete) {
        await (_db.update(_db.prayers)
              ..where((p) => p.id.equals(remoteOp.entityId)))
            .write(PrayersCompanion(
          deleted: const Value(1),
          updatedAt: Value(remoteOp.payload['updatedAt'] as int),
          version: Value(remoteOp.payload['version'] as int),
        ));
      }
      return true;
    }

    // Field-level merge
    const mergeableFields = [
      'title', 'content', 'frequency', 'status',
      'category', 'reminderAt', 'answeredAt',
    ];

    final mergeResult = _fieldMerger.merge(
      localFields: {
        'title': localPrayer.title,
        'content': localPrayer.content,
        'frequency': localPrayer.frequency,
        'status': localPrayer.status,
        'category': localPrayer.category,
        'reminderAt': localPrayer.reminderAt,
        'answeredAt': localPrayer.answeredAt,
      },
      localFieldTimestamps: _parseFieldTimestamps(localPrayer.fieldUpdatedAt),
      localUpdatedAt: localPrayer.updatedAt,
      localVersion: localPrayer.version,
      remoteFields: {
        'title': remoteOp.payload['title'],
        'content': remoteOp.payload['content'] ?? '',
        'frequency': remoteOp.payload['frequency'] ?? 'daily',
        'status': remoteOp.payload['status'] ?? 'active',
        'category': remoteOp.payload['category'],
        'reminderAt': remoteOp.payload['reminderAt'],
        'answeredAt': remoteOp.payload['answeredAt'],
      },
      remoteFieldTimestamps: _parseFieldTimestamps(
        remoteOp.payload['fieldUpdatedAt'],
      ),
      remoteUpdatedAt: remoteOp.payload['updatedAt'] as int,
      remoteVersion: remoteOp.payload['version'] as int,
      localDeviceId: _localDeviceId ?? '',
      remoteDeviceId: remoteOp.deviceId,
      mergeableFieldNames: mergeableFields,
    );

    await (_db.update(_db.prayers)
          ..where((p) => p.id.equals(remoteOp.entityId)))
        .write(PrayersCompanion(
      title: Value(mergeResult.mergedFields['title'] as String),
      content: Value(mergeResult.mergedFields['content'] as String),
      frequency: Value(mergeResult.mergedFields['frequency'] as String),
      status: Value(mergeResult.mergedFields['status'] as String),
      category: Value(mergeResult.mergedFields['category'] as String?),
      reminderAt: Value(mergeResult.mergedFields['reminderAt'] as int?),
      answeredAt: Value(mergeResult.mergedFields['answeredAt'] as int?),
      updatedAt: Value(mergeResult.mergedUpdatedAt),
      version: Value(mergeResult.mergedVersion),
      fieldUpdatedAt: Value(jsonEncode(mergeResult.mergedFieldTimestamps)),
    ));

    return true;
  }

  /// Apply a user profile operation from remote using field-level merge.
  Future<bool> _applyUserProfileOperation(OplogEntry remoteOp) async {
    final localProfile = await (_db.select(_db.userProfiles)
          ..where((p) => p.id.equals(remoteOp.entityId)))
        .getSingleOrNull();

    if (localProfile == null) {
      if (remoteOp.operation != OplogOperation.delete) {
        await _db.into(_db.userProfiles).insert(
              UserProfilesCompanion(
                id: Value(remoteOp.payload['id'] as String),
                userId: Value(remoteOp.payload['userId'] as String),
                username: Value(remoteOp.payload['username'] as String),
                displayName:
                    Value(remoteOp.payload['displayName'] as String? ?? ''),
                bio: Value(remoteOp.payload['bio'] as String? ?? ''),
                imageUrl: Value(remoteOp.payload['imageUrl'] as String?),
                friendRequestsEnabled: Value(
                  _asIntFlag(remoteOp.payload['friendRequestsEnabled'] ?? 1),
                ),
                updatedAt: Value(remoteOp.payload['updatedAt'] as int),
                version: Value(remoteOp.payload['version'] as int),
                deleted: Value(_asIntFlag(remoteOp.payload['deleted'])),
                createdAt: Value(remoteOp.payload['createdAt'] as int),
                fieldUpdatedAt: Value(
                  jsonEncode(_parseFieldTimestamps(remoteOp.payload['fieldUpdatedAt'])),
                ),
              ),
              mode: InsertMode.insertOrReplace,
            );
      }
      return false;
    }

    final remoteIsDelete = remoteOp.operation == OplogOperation.delete;
    final localIsDelete = localProfile.deleted == 1;
    if (remoteIsDelete || localIsDelete) {
      if (remoteIsDelete) {
        await (_db.update(_db.userProfiles)
              ..where((p) => p.id.equals(remoteOp.entityId)))
            .write(UserProfilesCompanion(
          deleted: const Value(1),
          updatedAt: Value(remoteOp.payload['updatedAt'] as int),
          version: Value(remoteOp.payload['version'] as int),
        ));
      }
      return true;
    }

    // Field-level merge
    const mergeableFields = [
      'username', 'displayName', 'bio', 'imageUrl', 'friendRequestsEnabled',
    ];

    final mergeResult = _fieldMerger.merge(
      localFields: {
        'username': localProfile.username,
        'displayName': localProfile.displayName,
        'bio': localProfile.bio,
        'imageUrl': localProfile.imageUrl,
        'friendRequestsEnabled': localProfile.friendRequestsEnabled,
      },
      localFieldTimestamps:
          _parseFieldTimestamps(localProfile.fieldUpdatedAt),
      localUpdatedAt: localProfile.updatedAt,
      localVersion: localProfile.version,
      remoteFields: {
        'username': remoteOp.payload['username'],
        'displayName': remoteOp.payload['displayName'] ?? '',
        'bio': remoteOp.payload['bio'] ?? '',
        'imageUrl': remoteOp.payload['imageUrl'],
        'friendRequestsEnabled':
            _asIntFlag(remoteOp.payload['friendRequestsEnabled'] ?? 1),
      },
      remoteFieldTimestamps: _parseFieldTimestamps(
        remoteOp.payload['fieldUpdatedAt'],
      ),
      remoteUpdatedAt: remoteOp.payload['updatedAt'] as int,
      remoteVersion: remoteOp.payload['version'] as int,
      localDeviceId: _localDeviceId ?? '',
      remoteDeviceId: remoteOp.deviceId,
      mergeableFieldNames: mergeableFields,
    );

    await (_db.update(_db.userProfiles)
          ..where((p) => p.id.equals(remoteOp.entityId)))
        .write(UserProfilesCompanion(
      username: Value(mergeResult.mergedFields['username'] as String),
      displayName: Value(mergeResult.mergedFields['displayName'] as String),
      bio: Value(mergeResult.mergedFields['bio'] as String),
      imageUrl: Value(mergeResult.mergedFields['imageUrl'] as String?),
      friendRequestsEnabled:
          Value(mergeResult.mergedFields['friendRequestsEnabled'] as int),
      updatedAt: Value(mergeResult.mergedUpdatedAt),
      version: Value(mergeResult.mergedVersion),
      fieldUpdatedAt: Value(jsonEncode(mergeResult.mergedFieldTimestamps)),
    ));

    return true;
  }

  /// Apply a group operation from remote using field-level merge.
  Future<bool> _applyGroupOperation(OplogEntry remoteOp) async {
    final localGroup = await (_db.select(_db.groups)
          ..where((g) => g.id.equals(remoteOp.entityId)))
        .getSingleOrNull();

    if (localGroup == null) {
      if (remoteOp.operation != OplogOperation.delete) {
        await _db.into(_db.groups).insert(
              GroupsCompanion(
                id: Value(remoteOp.payload['id'] as String),
                name: Value(remoteOp.payload['name'] as String),
                description:
                    Value(remoteOp.payload['description'] as String? ?? ''),
                groupType:
                    Value(remoteOp.payload['groupType'] as String? ?? 'church'),
                imageUrl: Value(remoteOp.payload['imageUrl'] as String?),
                joinCode:
                    Value(remoteOp.payload['joinCode'] as String? ?? ''),
                joinPolicy: Value(
                    remoteOp.payload['joinPolicy'] as String? ?? 'codeOnly'),
                createdByUserId:
                    Value(remoteOp.payload['createdByUserId'] as String),
                userId: Value(remoteOp.payload['userId'] as String),
                updatedAt: Value(remoteOp.payload['updatedAt'] as int),
                version: Value(remoteOp.payload['version'] as int),
                deleted: Value(_asIntFlag(remoteOp.payload['deleted'])),
                createdAt: Value(remoteOp.payload['createdAt'] as int),
                fieldUpdatedAt: Value(
                  jsonEncode(_parseFieldTimestamps(remoteOp.payload['fieldUpdatedAt'])),
                ),
              ),
              mode: InsertMode.insertOrReplace,
            );
      }
      return false;
    }

    final remoteIsDelete = remoteOp.operation == OplogOperation.delete;
    final localIsDelete = localGroup.deleted == 1;
    if (remoteIsDelete || localIsDelete) {
      if (remoteIsDelete) {
        await (_db.update(_db.groups)
              ..where((g) => g.id.equals(remoteOp.entityId)))
            .write(GroupsCompanion(
          deleted: const Value(1),
          updatedAt: Value(remoteOp.payload['updatedAt'] as int),
          version: Value(remoteOp.payload['version'] as int),
        ));
      }
      return true;
    }

    // Field-level merge (joinCode, createdByUserId are immutable)
    const mergeableFields = [
      'name', 'description', 'groupType', 'imageUrl', 'joinPolicy',
    ];

    final mergeResult = _fieldMerger.merge(
      localFields: {
        'name': localGroup.name,
        'description': localGroup.description,
        'groupType': localGroup.groupType,
        'imageUrl': localGroup.imageUrl,
        'joinPolicy': localGroup.joinPolicy,
      },
      localFieldTimestamps:
          _parseFieldTimestamps(localGroup.fieldUpdatedAt),
      localUpdatedAt: localGroup.updatedAt,
      localVersion: localGroup.version,
      remoteFields: {
        'name': remoteOp.payload['name'],
        'description': remoteOp.payload['description'] ?? '',
        'groupType': remoteOp.payload['groupType'] ?? 'church',
        'imageUrl': remoteOp.payload['imageUrl'],
        'joinPolicy': remoteOp.payload['joinPolicy'] ?? 'codeOnly',
      },
      remoteFieldTimestamps: _parseFieldTimestamps(
        remoteOp.payload['fieldUpdatedAt'],
      ),
      remoteUpdatedAt: remoteOp.payload['updatedAt'] as int,
      remoteVersion: remoteOp.payload['version'] as int,
      localDeviceId: _localDeviceId ?? '',
      remoteDeviceId: remoteOp.deviceId,
      mergeableFieldNames: mergeableFields,
    );

    await (_db.update(_db.groups)
          ..where((g) => g.id.equals(remoteOp.entityId)))
        .write(GroupsCompanion(
      name: Value(mergeResult.mergedFields['name'] as String),
      description: Value(mergeResult.mergedFields['description'] as String),
      groupType: Value(mergeResult.mergedFields['groupType'] as String),
      imageUrl: Value(mergeResult.mergedFields['imageUrl'] as String?),
      joinPolicy: Value(mergeResult.mergedFields['joinPolicy'] as String),
      updatedAt: Value(mergeResult.mergedUpdatedAt),
      version: Value(mergeResult.mergedVersion),
      fieldUpdatedAt: Value(jsonEncode(mergeResult.mergedFieldTimestamps)),
    ));

    return true;
  }

  /// Apply a promise operation from remote
  Future<bool> _applyPromiseOperation(OplogEntry remoteOp) async {
    final localPromise = await (_db.select(_db.promises)
          ..where((p) => p.id.equals(remoteOp.entityId)))
        .getSingleOrNull();

    if (localPromise == null) {
      if (remoteOp.operation != OplogOperation.delete) {
        await _db.into(_db.promises).insert(
              PromisesCompanion(
                id: Value(remoteOp.payload['id'] as String),
                userId: Value(remoteOp.payload['userId'] as String),
                reference: Value(remoteOp.payload['reference'] as String),
                content: Value(remoteOp.payload['content'] as String),
                preview: Value(remoteOp.payload['preview'] as String? ?? ''),
                notes: Value(remoteOp.payload['notes'] as String? ?? ''),
                category: Value(remoteOp.payload['category'] as String?),
                isFavorite: Value(_asIntFlag(remoteOp.payload['isFavorite'])),
                updatedAt: Value(remoteOp.payload['updatedAt'] as int),
                version: Value(remoteOp.payload['version'] as int),
                deleted: Value(_asIntFlag(remoteOp.payload['deleted'])),
                trashedAt: Value(remoteOp.payload['trashedAt'] as int?),
                createdAt: Value(remoteOp.payload['createdAt'] as int),
              ),
              mode: InsertMode.insertOrReplace,
            );
      }
      return false;
    }

    final resolution = _conflictResolver.resolvePromise(
      entityId: remoteOp.entityId,
      localVersion: localPromise.version,
      localUpdatedAt: localPromise.updatedAt,
      remoteVersion: remoteOp.entityVersion,
      remoteUpdatedAt: remoteOp.payload['updatedAt'] as int,
      remoteIsDelete: remoteOp.operation == OplogOperation.delete,
      localIsDelete: localPromise.deleted == 1,
      localDeviceId: _localDeviceId,
      remoteDeviceId: remoteOp.deviceId,
    );

    if (resolution.useRemote) {
      await (_db.update(_db.promises)
            ..where((p) => p.id.equals(remoteOp.entityId)))
          .write(
        PromisesCompanion(
          reference: Value(remoteOp.payload['reference'] as String),
          content: Value(remoteOp.payload['content'] as String),
          preview: Value(remoteOp.payload['preview'] as String? ?? ''),
          notes: Value(remoteOp.payload['notes'] as String? ?? ''),
          category: Value(remoteOp.payload['category'] as String?),
          isFavorite: Value(_asIntFlag(remoteOp.payload['isFavorite'])),
          updatedAt: Value(remoteOp.payload['updatedAt'] as int),
          version: Value(remoteOp.payload['version'] as int),
          deleted: Value(_asIntFlag(remoteOp.payload['deleted'])),
          trashedAt: Value(remoteOp.payload['trashedAt'] as int?),
        ),
      );
    }

    return resolution.hadConflict;
  }

  /// Apply a person operation from remote
  Future<bool> _applyPersonOperation(OplogEntry remoteOp) async {
    SyncLogger.info(
      'Applying person op: ${remoteOp.operation.toDbValue()} '
      'id=${remoteOp.entityId}, payload keys=${remoteOp.payload.keys.toList()}',
    );

    final p = remoteOp.payload;
    final localPerson = await (_db.select(_db.people)
          ..where((t) => t.id.equals(remoteOp.entityId)))
        .getSingleOrNull();

    if (localPerson == null) {
      if (remoteOp.operation != OplogOperation.delete) {
        await _db.into(_db.people).insert(
              PeopleCompanion(
                id: Value(p['id'] as String),
                userId: Value(p['userId'] as String),
                name: Value(p['name'] as String),
                relation: Value(p['relation'] as String? ?? ''),
                church: Value(p['church'] as String?),
                email: Value(p['email'] as String?),
                phone: Value(p['phone'] as String?),
                notes: Value(p['notes'] as String? ?? ''),
                imageUrl: Value(p['imageUrl'] as String?),
                updatedAt: Value((p['updatedAt'] as num).toInt()),
                version: Value((p['version'] as num).toInt()),
                deleted: Value(_asIntFlag(p['deleted'])),
                createdAt: Value((p['createdAt'] as num).toInt()),
              ),
              mode: InsertMode.insertOrReplace,
            );
        SyncLogger.info('Person inserted: ${remoteOp.entityId}');
      }
      return false;
    }

    final resolution = _conflictResolver.resolvePerson(
      entityId: remoteOp.entityId,
      localVersion: localPerson.version,
      localUpdatedAt: localPerson.updatedAt,
      remoteVersion: remoteOp.entityVersion,
      remoteUpdatedAt: (p['updatedAt'] as num).toInt(),
      remoteIsDelete: remoteOp.operation == OplogOperation.delete,
      localIsDelete: localPerson.deleted == 1,
      localDeviceId: _localDeviceId,
      remoteDeviceId: remoteOp.deviceId,
    );

    if (resolution.useRemote) {
      await (_db.update(_db.people)
            ..where((t) => t.id.equals(remoteOp.entityId)))
          .write(
        PeopleCompanion(
          name: Value(p['name'] as String),
          relation: Value(p['relation'] as String? ?? ''),
          church: Value(p['church'] as String?),
          email: Value(p['email'] as String?),
          phone: Value(p['phone'] as String?),
          notes: Value(p['notes'] as String? ?? ''),
          imageUrl: Value(p['imageUrl'] as String?),
          updatedAt: Value((p['updatedAt'] as num).toInt()),
          version: Value((p['version'] as num).toInt()),
          deleted: Value(_asIntFlag(p['deleted'])),
        ),
      );
    }

    return resolution.hadConflict;
  }

  /// Apply a song operation from remote
  Future<bool> _applySongOperation(OplogEntry remoteOp) async {
    final localSong = await (_db.select(_db.songs)
          ..where((s) => s.id.equals(remoteOp.entityId)))
        .getSingleOrNull();

    if (localSong == null) {
      if (remoteOp.operation != OplogOperation.delete) {
        await _db.into(_db.songs).insert(
              SongsCompanion(
                id: Value(remoteOp.payload['id'] as String),
                userId: Value(remoteOp.payload['userId'] as String),
                title: Value(remoteOp.payload['title'] as String),
                folderId: Value(remoteOp.payload['folderId'] as String?),
                lyrics: Value(remoteOp.payload['lyrics'] as String? ?? ''),
                chords: Value(remoteOp.payload['chords'] as String? ?? ''),
                language: Value(remoteOp.payload['language'] as String? ?? 'English'),
                book: Value(remoteOp.payload['book'] as String?),
                preview: Value(remoteOp.payload['preview'] as String? ?? ''),
                tags: Value(remoteOp.payload['tags'] as String? ?? ''),
                scale: Value(remoteOp.payload['scale'] as String? ?? ''),
                chordLines: Value(remoteOp.payload['chordLines'] as String? ?? ''),
                notes: Value(remoteOp.payload['notes'] as String? ?? ''),
                hasChords: Value(_asIntFlag(remoteOp.payload['hasChords'])),
                isFavorite: Value(_asIntFlag(remoteOp.payload['isFavorite'])),
                updatedAt: Value(remoteOp.payload['updatedAt'] as int),
                version: Value(remoteOp.payload['version'] as int),
                deleted: Value(_asIntFlag(remoteOp.payload['deleted'])),
                trashedAt: Value(remoteOp.payload['trashedAt'] as int?),
                createdAt: Value(remoteOp.payload['createdAt'] as int),
              ),
              mode: InsertMode.insertOrReplace,
            );
      }
      return false;
    }

    final resolution = _conflictResolver.resolveSong(
      entityId: remoteOp.entityId,
      localVersion: localSong.version,
      localUpdatedAt: localSong.updatedAt,
      remoteVersion: remoteOp.entityVersion,
      remoteUpdatedAt: remoteOp.payload['updatedAt'] as int,
      remoteIsDelete: remoteOp.operation == OplogOperation.delete,
      localIsDelete: localSong.deleted == 1,
      localDeviceId: _localDeviceId,
      remoteDeviceId: remoteOp.deviceId,
    );

    if (resolution.useRemote) {
      await (_db.update(_db.songs)
            ..where((s) => s.id.equals(remoteOp.entityId)))
          .write(
        SongsCompanion(
          title: Value(remoteOp.payload['title'] as String),
          folderId: Value(remoteOp.payload['folderId'] as String?),
          lyrics: Value(remoteOp.payload['lyrics'] as String? ?? ''),
          chords: Value(remoteOp.payload['chords'] as String? ?? ''),
          language: Value(remoteOp.payload['language'] as String? ?? 'English'),
          book: Value(remoteOp.payload['book'] as String?),
          preview: Value(remoteOp.payload['preview'] as String? ?? ''),
          tags: Value(remoteOp.payload['tags'] as String? ?? ''),
          scale: Value(remoteOp.payload['scale'] as String? ?? ''),
          chordLines: Value(remoteOp.payload['chordLines'] as String? ?? ''),
          notes: Value(remoteOp.payload['notes'] as String? ?? ''),
          hasChords: Value(_asIntFlag(remoteOp.payload['hasChords'])),
          isFavorite: Value(_asIntFlag(remoteOp.payload['isFavorite'])),
          updatedAt: Value(remoteOp.payload['updatedAt'] as int),
          version: Value(remoteOp.payload['version'] as int),
          deleted: Value(_asIntFlag(remoteOp.payload['deleted'])),
          trashedAt: Value(remoteOp.payload['trashedAt'] as int?),
        ),
      );
    }

    return resolution.hadConflict;
  }

  Future<bool> _applyPrayerLogOperation(OplogEntry remoteOp) async {
    final local = await (_db.select(_db.prayerLogs)
          ..where((p) => p.id.equals(remoteOp.entityId)))
        .getSingleOrNull();
    return _applyGeneric(
      localVersion: local?.version,
      localUpdatedAt: local?.updatedAt,
      localIsDeleted: local != null && local.deleted == 1,
      remoteOp: remoteOp,
      onInsert: () async {
        await _db.into(_db.prayerLogs).insert(
              PrayerLogsCompanion(
                id: Value(remoteOp.payload['id'] as String),
                prayerId: Value(remoteOp.payload['prayerId'] as String),
                userId: Value(remoteOp.payload['userId'] as String),
                note: Value(remoteOp.payload['note'] as String? ?? ''),
                loggedAt: Value(remoteOp.payload['loggedAt'] as int),
                sessionDate: Value(remoteOp.payload['sessionDate'] as String),
                updatedAt: Value(remoteOp.payload['updatedAt'] as int),
                version: Value(remoteOp.payload['version'] as int),
                deleted: Value(_asIntFlag(remoteOp.payload['deleted'])),
                createdAt: Value(remoteOp.payload['createdAt'] as int),
              ),
              mode: InsertMode.insertOrReplace,
            );
      },
      onUpdate: () async {
        await (_db.update(_db.prayerLogs)
              ..where((p) => p.id.equals(remoteOp.entityId)))
            .write(
          PrayerLogsCompanion(
            prayerId: Value(remoteOp.payload['prayerId'] as String),
            userId: Value(remoteOp.payload['userId'] as String),
            note: Value(remoteOp.payload['note'] as String? ?? ''),
            loggedAt: Value(remoteOp.payload['loggedAt'] as int),
            sessionDate: Value(remoteOp.payload['sessionDate'] as String),
            updatedAt: Value(remoteOp.payload['updatedAt'] as int),
            version: Value(remoteOp.payload['version'] as int),
            deleted: Value(_asIntFlag(remoteOp.payload['deleted'])),
          ),
        );
      },
    );
  }

  Future<bool> _applyPreacherOperation(OplogEntry remoteOp) async {
    final local = await (_db.select(_db.syncPreachers)
          ..where((p) => p.id.equals(remoteOp.entityId)))
        .getSingleOrNull();
    return _applyGeneric(
      localVersion: local?.version,
      localUpdatedAt: local?.updatedAt,
      localIsDeleted: local != null && local.deleted == 1,
      remoteOp: remoteOp,
      onInsert: () async {
        await _db.into(_db.syncPreachers).insert(
              SyncPreachersCompanion(
                id: Value(remoteOp.payload['id'] as String),
                userId: Value(remoteOp.payload['userId'] as String),
                name: Value(remoteOp.payload['name'] as String),
                updatedAt: Value(remoteOp.payload['updatedAt'] as int),
                version: Value(remoteOp.payload['version'] as int),
                deleted: Value(_asIntFlag(remoteOp.payload['deleted'])),
                createdAt: Value(remoteOp.payload['createdAt'] as int),
              ),
              mode: InsertMode.insertOrReplace,
            );
      },
      onUpdate: () async {
        await (_db.update(_db.syncPreachers)
              ..where((p) => p.id.equals(remoteOp.entityId)))
            .write(
          SyncPreachersCompanion(
            userId: Value(remoteOp.payload['userId'] as String),
            name: Value(remoteOp.payload['name'] as String),
            updatedAt: Value(remoteOp.payload['updatedAt'] as int),
            version: Value(remoteOp.payload['version'] as int),
            deleted: Value(_asIntFlag(remoteOp.payload['deleted'])),
          ),
        );
      },
    );
  }

  Future<bool> _applyTagOperation(OplogEntry remoteOp) async {
    final local = await (_db.select(_db.syncTags)
          ..where((t) => t.id.equals(remoteOp.entityId)))
        .getSingleOrNull();
    return _applyGeneric(
      localVersion: local?.version,
      localUpdatedAt: local?.updatedAt,
      localIsDeleted: local != null && local.deleted == 1,
      remoteOp: remoteOp,
      onInsert: () async {
        await _db.into(_db.syncTags).insert(
              SyncTagsCompanion(
                id: Value(remoteOp.payload['id'] as String),
                userId: Value(remoteOp.payload['userId'] as String),
                name: Value(remoteOp.payload['name'] as String),
                updatedAt: Value(remoteOp.payload['updatedAt'] as int),
                version: Value(remoteOp.payload['version'] as int),
                deleted: Value(_asIntFlag(remoteOp.payload['deleted'])),
                createdAt: Value(remoteOp.payload['createdAt'] as int),
              ),
              mode: InsertMode.insertOrReplace,
            );
      },
      onUpdate: () async {
        await (_db.update(_db.syncTags)
              ..where((t) => t.id.equals(remoteOp.entityId)))
            .write(
          SyncTagsCompanion(
            userId: Value(remoteOp.payload['userId'] as String),
            name: Value(remoteOp.payload['name'] as String),
            updatedAt: Value(remoteOp.payload['updatedAt'] as int),
            version: Value(remoteOp.payload['version'] as int),
            deleted: Value(_asIntFlag(remoteOp.payload['deleted'])),
          ),
        );
      },
    );
  }

  Future<bool> _applyNoteTagOperation(OplogEntry remoteOp) async {
    final local = await (_db.select(_db.syncNoteTags)
          ..where((n) => n.id.equals(remoteOp.entityId)))
        .getSingleOrNull();
    return _applyGeneric(
      localVersion: local?.version,
      localUpdatedAt: local?.updatedAt,
      localIsDeleted: local != null && local.deleted == 1,
      remoteOp: remoteOp,
      onInsert: () async {
        await _db.into(_db.syncNoteTags).insert(
              SyncNoteTagsCompanion(
                id: Value(remoteOp.payload['id'] as String),
                noteId: Value(remoteOp.payload['noteId'] as String),
                tagId: Value(remoteOp.payload['tagId'] as String),
                userId: Value(remoteOp.payload['userId'] as String),
                updatedAt: Value(remoteOp.payload['updatedAt'] as int),
                version: Value(remoteOp.payload['version'] as int),
                deleted: Value(_asIntFlag(remoteOp.payload['deleted'])),
                createdAt: Value(remoteOp.payload['createdAt'] as int),
              ),
              mode: InsertMode.insertOrReplace,
            );
      },
      onUpdate: () async {
        await (_db.update(_db.syncNoteTags)
              ..where((n) => n.id.equals(remoteOp.entityId)))
            .write(
          SyncNoteTagsCompanion(
            noteId: Value(remoteOp.payload['noteId'] as String),
            tagId: Value(remoteOp.payload['tagId'] as String),
            userId: Value(remoteOp.payload['userId'] as String),
            updatedAt: Value(remoteOp.payload['updatedAt'] as int),
            version: Value(remoteOp.payload['version'] as int),
            deleted: Value(_asIntFlag(remoteOp.payload['deleted'])),
          ),
        );
      },
    );
  }

  Future<bool> _applySongTagOperation(OplogEntry remoteOp) async {
    final local = await (_db.select(_db.syncSongTags)
          ..where((s) => s.id.equals(remoteOp.entityId)))
        .getSingleOrNull();
    return _applyGeneric(
      localVersion: local?.version,
      localUpdatedAt: local?.updatedAt,
      localIsDeleted: local != null && local.deleted == 1,
      remoteOp: remoteOp,
      onInsert: () async {
        await _db.into(_db.syncSongTags).insert(
              SyncSongTagsCompanion(
                id: Value(remoteOp.payload['id'] as String),
                songId: Value(remoteOp.payload['songId'] as String),
                tagId: Value(remoteOp.payload['tagId'] as String),
                userId: Value(remoteOp.payload['userId'] as String),
                updatedAt: Value(remoteOp.payload['updatedAt'] as int),
                version: Value(remoteOp.payload['version'] as int),
                deleted: Value(_asIntFlag(remoteOp.payload['deleted'])),
                createdAt: Value(remoteOp.payload['createdAt'] as int),
              ),
              mode: InsertMode.insertOrReplace,
            );
      },
      onUpdate: () async {
        await (_db.update(_db.syncSongTags)
              ..where((s) => s.id.equals(remoteOp.entityId)))
            .write(
          SyncSongTagsCompanion(
            songId: Value(remoteOp.payload['songId'] as String),
            tagId: Value(remoteOp.payload['tagId'] as String),
            userId: Value(remoteOp.payload['userId'] as String),
            updatedAt: Value(remoteOp.payload['updatedAt'] as int),
            version: Value(remoteOp.payload['version'] as int),
            deleted: Value(_asIntFlag(remoteOp.payload['deleted'])),
          ),
        );
      },
    );
  }

  Future<bool> _applyPrayerUpdateOperation(OplogEntry remoteOp) async {
    final local = await (_db.select(_db.prayerUpdates)
          ..where((p) => p.id.equals(remoteOp.entityId)))
        .getSingleOrNull();
    return _applyGeneric(
      localVersion: local?.version,
      localUpdatedAt: local?.updatedAt,
      localIsDeleted: local != null && local.deleted == 1,
      remoteOp: remoteOp,
      onInsert: () async {
        await _db.into(_db.prayerUpdates).insert(
              PrayerUpdatesCompanion(
                id: Value(remoteOp.payload['id'] as String),
                prayerId: Value(remoteOp.payload['prayerId'] as String),
                userId: Value(remoteOp.payload['userId'] as String),
                content: Value(remoteOp.payload['content'] as String),
                updatedAt: Value(remoteOp.payload['updatedAt'] as int),
                version: Value(remoteOp.payload['version'] as int),
                deleted: Value(_asIntFlag(remoteOp.payload['deleted'])),
                createdAt: Value(remoteOp.payload['createdAt'] as int),
              ),
              mode: InsertMode.insertOrReplace,
            );
      },
      onUpdate: () async {
        await (_db.update(_db.prayerUpdates)
              ..where((p) => p.id.equals(remoteOp.entityId)))
            .write(
          PrayerUpdatesCompanion(
            prayerId: Value(remoteOp.payload['prayerId'] as String),
            userId: Value(remoteOp.payload['userId'] as String),
            content: Value(remoteOp.payload['content'] as String),
            updatedAt: Value(remoteOp.payload['updatedAt'] as int),
            version: Value(remoteOp.payload['version'] as int),
            deleted: Value(_asIntFlag(remoteOp.payload['deleted'])),
          ),
        );
      },
    );
  }

  Future<bool> _applyPromiseConditionOperation(OplogEntry remoteOp) async {
    final local = await (_db.select(_db.promiseConditions)
          ..where((p) => p.id.equals(remoteOp.entityId)))
        .getSingleOrNull();
    return _applyGeneric(
      localVersion: local?.version,
      localUpdatedAt: local?.updatedAt,
      localIsDeleted: local != null && local.deleted == 1,
      remoteOp: remoteOp,
      onInsert: () async {
        await _db.into(_db.promiseConditions).insert(
              PromiseConditionsCompanion(
                id: Value(remoteOp.payload['id'] as String),
                promiseId: Value(remoteOp.payload['promiseId'] as String),
                userId: Value(remoteOp.payload['userId'] as String),
                description: Value(remoteOp.payload['description'] as String),
                notes: Value(remoteOp.payload['notes'] as String? ?? ''),
                status: Value(remoteOp.payload['status'] as String),
                updatedAt: Value(remoteOp.payload['updatedAt'] as int),
                version: Value(remoteOp.payload['version'] as int),
                deleted: Value(_asIntFlag(remoteOp.payload['deleted'])),
                createdAt: Value(remoteOp.payload['createdAt'] as int),
              ),
              mode: InsertMode.insertOrReplace,
            );
      },
      onUpdate: () async {
        await (_db.update(_db.promiseConditions)
              ..where((p) => p.id.equals(remoteOp.entityId)))
            .write(
          PromiseConditionsCompanion(
            promiseId: Value(remoteOp.payload['promiseId'] as String),
            userId: Value(remoteOp.payload['userId'] as String),
            description: Value(remoteOp.payload['description'] as String),
            notes: Value(remoteOp.payload['notes'] as String? ?? ''),
            status: Value(remoteOp.payload['status'] as String),
            updatedAt: Value(remoteOp.payload['updatedAt'] as int),
            version: Value(remoteOp.payload['version'] as int),
            deleted: Value(_asIntFlag(remoteOp.payload['deleted'])),
          ),
        );
      },
    );
  }

  Future<bool> _applyPromiseTagOperation(OplogEntry remoteOp) async {
    final local = await (_db.select(_db.syncPromiseTags)
          ..where((p) => p.id.equals(remoteOp.entityId)))
        .getSingleOrNull();
    return _applyGeneric(
      localVersion: local?.version,
      localUpdatedAt: local?.updatedAt,
      localIsDeleted: local != null && local.deleted == 1,
      remoteOp: remoteOp,
      onInsert: () async {
        await _db.into(_db.syncPromiseTags).insert(
              SyncPromiseTagsCompanion(
                id: Value(remoteOp.payload['id'] as String),
                promiseId: Value(remoteOp.payload['promiseId'] as String),
                tagId: Value(remoteOp.payload['tagId'] as String),
                userId: Value(remoteOp.payload['userId'] as String),
                updatedAt: Value(remoteOp.payload['updatedAt'] as int),
                version: Value(remoteOp.payload['version'] as int),
                deleted: Value(_asIntFlag(remoteOp.payload['deleted'])),
                createdAt: Value(remoteOp.payload['createdAt'] as int),
              ),
              mode: InsertMode.insertOrReplace,
            );
      },
      onUpdate: () async {
        await (_db.update(_db.syncPromiseTags)
              ..where((p) => p.id.equals(remoteOp.entityId)))
            .write(
          SyncPromiseTagsCompanion(
            promiseId: Value(remoteOp.payload['promiseId'] as String),
            tagId: Value(remoteOp.payload['tagId'] as String),
            userId: Value(remoteOp.payload['userId'] as String),
            updatedAt: Value(remoteOp.payload['updatedAt'] as int),
            version: Value(remoteOp.payload['version'] as int),
            deleted: Value(_asIntFlag(remoteOp.payload['deleted'])),
          ),
        );
      },
    );
  }

  Future<bool> _applyPrayerTagOperation(OplogEntry remoteOp) async {
    final local = await (_db.select(_db.syncPrayerTags)
          ..where((p) => p.id.equals(remoteOp.entityId)))
        .getSingleOrNull();
    return _applyGeneric(
      localVersion: local?.version,
      localUpdatedAt: local?.updatedAt,
      localIsDeleted: local != null && local.deleted == 1,
      remoteOp: remoteOp,
      onInsert: () async {
        await _db.into(_db.syncPrayerTags).insert(
              SyncPrayerTagsCompanion(
                id: Value(remoteOp.payload['id'] as String),
                prayerId: Value(remoteOp.payload['prayerId'] as String),
                tagId: Value(remoteOp.payload['tagId'] as String),
                userId: Value(remoteOp.payload['userId'] as String),
                updatedAt: Value(remoteOp.payload['updatedAt'] as int),
                version: Value(remoteOp.payload['version'] as int),
                deleted: Value(_asIntFlag(remoteOp.payload['deleted'])),
                createdAt: Value(remoteOp.payload['createdAt'] as int),
              ),
              mode: InsertMode.insertOrReplace,
            );
      },
      onUpdate: () async {
        await (_db.update(_db.syncPrayerTags)
              ..where((p) => p.id.equals(remoteOp.entityId)))
            .write(
          SyncPrayerTagsCompanion(
            prayerId: Value(remoteOp.payload['prayerId'] as String),
            tagId: Value(remoteOp.payload['tagId'] as String),
            userId: Value(remoteOp.payload['userId'] as String),
            updatedAt: Value(remoteOp.payload['updatedAt'] as int),
            version: Value(remoteOp.payload['version'] as int),
            deleted: Value(_asIntFlag(remoteOp.payload['deleted'])),
          ),
        );
      },
    );
  }

  Future<bool> _applyPrayerPersonOperation(OplogEntry remoteOp) async {
    final local = await (_db.select(_db.syncPrayerPeople)
          ..where((p) => p.id.equals(remoteOp.entityId)))
        .getSingleOrNull();
    return _applyGeneric(
      localVersion: local?.version,
      localUpdatedAt: local?.updatedAt,
      localIsDeleted: local != null && local.deleted == 1,
      remoteOp: remoteOp,
      onInsert: () async {
        await _db.into(_db.syncPrayerPeople).insert(
              SyncPrayerPeopleCompanion(
                id: Value(remoteOp.payload['id'] as String),
                prayerId: Value(remoteOp.payload['prayerId'] as String),
                personId: Value(remoteOp.payload['personId'] as String),
                userId: Value(remoteOp.payload['userId'] as String),
                updatedAt: Value(remoteOp.payload['updatedAt'] as int),
                version: Value(remoteOp.payload['version'] as int),
                deleted: Value(_asIntFlag(remoteOp.payload['deleted'])),
                createdAt: Value(remoteOp.payload['createdAt'] as int),
              ),
              mode: InsertMode.insertOrReplace,
            );
      },
      onUpdate: () async {
        await (_db.update(_db.syncPrayerPeople)
              ..where((p) => p.id.equals(remoteOp.entityId)))
            .write(
          SyncPrayerPeopleCompanion(
            prayerId: Value(remoteOp.payload['prayerId'] as String),
            personId: Value(remoteOp.payload['personId'] as String),
            userId: Value(remoteOp.payload['userId'] as String),
            updatedAt: Value(remoteOp.payload['updatedAt'] as int),
            version: Value(remoteOp.payload['version'] as int),
            deleted: Value(_asIntFlag(remoteOp.payload['deleted'])),
          ),
        );
      },
    );
  }

  Future<bool> _applyEntityAccessOperation(OplogEntry remoteOp) async {
    final local = await (_db.select(_db.entityAccess)
          ..where((e) => e.id.equals(remoteOp.entityId)))
        .getSingleOrNull();
    return _applyGeneric(
      localVersion: local?.version,
      localUpdatedAt: local?.updatedAt,
      localIsDeleted: local != null && local.deleted == 1,
      remoteOp: remoteOp,
      onInsert: () async {
        await _db.into(_db.entityAccess).insert(
              EntityAccessCompanion(
                id: Value(remoteOp.payload['id'] as String),
                entityType: Value(remoteOp.payload['entityType'] as String),
                entityId: Value(remoteOp.payload['entityId'] as String),
                accessType: Value(remoteOp.payload['accessType'] as String),
                targetId: Value(remoteOp.payload['targetId'] as String?),
                role: Value(remoteOp.payload['role'] as String? ?? 'viewer'),
                userId: Value(remoteOp.payload['userId'] as String),
                updatedAt: Value(remoteOp.payload['updatedAt'] as int),
                version: Value(remoteOp.payload['version'] as int),
                deleted: Value(_asIntFlag(remoteOp.payload['deleted'])),
                createdAt: Value(remoteOp.payload['createdAt'] as int),
              ),
              mode: InsertMode.insertOrReplace,
            );
      },
      onUpdate: () async {
        await (_db.update(_db.entityAccess)
              ..where((e) => e.id.equals(remoteOp.entityId)))
            .write(
          EntityAccessCompanion(
            entityType: Value(remoteOp.payload['entityType'] as String),
            entityId: Value(remoteOp.payload['entityId'] as String),
            accessType: Value(remoteOp.payload['accessType'] as String),
            targetId: Value(remoteOp.payload['targetId'] as String?),
            role: Value(remoteOp.payload['role'] as String? ?? 'viewer'),
            userId: Value(remoteOp.payload['userId'] as String),
            updatedAt: Value(remoteOp.payload['updatedAt'] as int),
            version: Value(remoteOp.payload['version'] as int),
            deleted: Value(_asIntFlag(remoteOp.payload['deleted'])),
          ),
        );
      },
    );
  }

  Future<bool> _applyPromisePrayerLinkOperation(OplogEntry remoteOp) async {
    final local = await (_db.select(_db.promisePrayerLinks)
          ..where((p) => p.id.equals(remoteOp.entityId)))
        .getSingleOrNull();
    return _applyGeneric(
      localVersion: local?.version,
      localUpdatedAt: local?.updatedAt,
      localIsDeleted: local != null && local.deleted == 1,
      remoteOp: remoteOp,
      onInsert: () async {
        await _db.into(_db.promisePrayerLinks).insert(
              PromisePrayerLinksCompanion(
                id: Value(remoteOp.payload['id'] as String),
                promiseId: Value(remoteOp.payload['promiseId'] as String),
                prayerId: Value(remoteOp.payload['prayerId'] as String),
                userId: Value(remoteOp.payload['userId'] as String),
                updatedAt: Value(remoteOp.payload['updatedAt'] as int),
                version: Value(remoteOp.payload['version'] as int),
                deleted: Value(_asIntFlag(remoteOp.payload['deleted'])),
                createdAt: Value(remoteOp.payload['createdAt'] as int),
              ),
              mode: InsertMode.insertOrReplace,
            );
      },
      onUpdate: () async {
        await (_db.update(_db.promisePrayerLinks)
              ..where((p) => p.id.equals(remoteOp.entityId)))
            .write(
          PromisePrayerLinksCompanion(
            promiseId: Value(remoteOp.payload['promiseId'] as String),
            prayerId: Value(remoteOp.payload['prayerId'] as String),
            userId: Value(remoteOp.payload['userId'] as String),
            updatedAt: Value(remoteOp.payload['updatedAt'] as int),
            version: Value(remoteOp.payload['version'] as int),
            deleted: Value(_asIntFlag(remoteOp.payload['deleted'])),
          ),
        );
      },
    );
  }

  Future<bool> _applyFeedbackThreadOperation(OplogEntry remoteOp) async {
    final local = await (_db.select(_db.feedbackThreads)
          ..where((t) => t.id.equals(remoteOp.entityId)))
        .getSingleOrNull();
    return _applyGeneric(
      localVersion: local?.version,
      localUpdatedAt: local?.updatedAt,
      localIsDeleted: local != null && local.deleted == 1,
      remoteOp: remoteOp,
      onInsert: () async {
        await _db.into(_db.feedbackThreads).insert(
              FeedbackThreadsCompanion(
                id: Value(remoteOp.payload['id'] as String),
                userId: Value(remoteOp.payload['userId'] as String),
                category: Value(remoteOp.payload['category'] as String),
                subject: Value(remoteOp.payload['subject'] as String),
                status: Value(remoteOp.payload['status'] as String? ?? 'open'),
                priority: Value(remoteOp.payload['priority'] as String? ?? 'medium'),
                lastMessageAt: Value(remoteOp.payload['lastMessageAt'] as int?),
                adminAssigned: Value(remoteOp.payload['adminAssigned'] as String?),
                unreadForUser: Value(remoteOp.payload['unreadForUser'] as int? ?? 0),
                unreadForAdmin: Value(remoteOp.payload['unreadForAdmin'] as int? ?? 0),
                deviceModel: Value(remoteOp.payload['deviceModel'] as String?),
                osVersion: Value(remoteOp.payload['osVersion'] as String?),
                appVersion: Value(remoteOp.payload['appVersion'] as String?),
                updatedAt: Value(remoteOp.payload['updatedAt'] as int),
                version: Value(remoteOp.payload['version'] as int),
                deleted: Value(_asIntFlag(remoteOp.payload['deleted'])),
                createdAt: Value(remoteOp.payload['createdAt'] as int),
                fieldUpdatedAt: Value(
                  jsonEncode(_parseFieldTimestamps(remoteOp.payload['fieldUpdatedAt'])),
                ),
              ),
              mode: InsertMode.insertOrReplace,
            );
      },
      onUpdate: () async {
        await (_db.update(_db.feedbackThreads)
              ..where((t) => t.id.equals(remoteOp.entityId)))
            .write(
          FeedbackThreadsCompanion(
            userId: Value(remoteOp.payload['userId'] as String),
            category: Value(remoteOp.payload['category'] as String),
            subject: Value(remoteOp.payload['subject'] as String),
            status: Value(remoteOp.payload['status'] as String? ?? 'open'),
            priority: Value(remoteOp.payload['priority'] as String? ?? 'medium'),
            lastMessageAt: Value(remoteOp.payload['lastMessageAt'] as int?),
            adminAssigned: Value(remoteOp.payload['adminAssigned'] as String?),
            unreadForUser: Value(remoteOp.payload['unreadForUser'] as int? ?? 0),
            unreadForAdmin: Value(remoteOp.payload['unreadForAdmin'] as int? ?? 0),
            deviceModel: Value(remoteOp.payload['deviceModel'] as String?),
            osVersion: Value(remoteOp.payload['osVersion'] as String?),
            appVersion: Value(remoteOp.payload['appVersion'] as String?),
            updatedAt: Value(remoteOp.payload['updatedAt'] as int),
            version: Value(remoteOp.payload['version'] as int),
            deleted: Value(_asIntFlag(remoteOp.payload['deleted'])),
            fieldUpdatedAt: Value(
              jsonEncode(remoteOp.payload['fieldUpdatedAt'] ?? {}),
            ),
          ),
        );
      },
    );
  }

  Future<bool> _applyFeedbackMessageOperation(OplogEntry remoteOp) async {
    final local = await (_db.select(_db.feedbackMessages)
          ..where((m) => m.id.equals(remoteOp.entityId)))
        .getSingleOrNull();
    return _applyGeneric(
      localVersion: local?.version,
      localUpdatedAt: local?.updatedAt,
      localIsDeleted: local != null && local.deleted == 1,
      remoteOp: remoteOp,
      onInsert: () async {
        await _db.into(_db.feedbackMessages).insert(
              FeedbackMessagesCompanion(
                id: Value(remoteOp.payload['id'] as String),
                threadId: Value(remoteOp.payload['threadId'] as String),
                userId: Value(remoteOp.payload['userId'] as String),
                message: Value(remoteOp.payload['message'] as String),
                senderType: Value(remoteOp.payload['senderType'] as String? ?? 'user'),
                hasAttachments: Value(remoteOp.payload['hasAttachments'] as int? ?? 0),
                updatedAt: Value(remoteOp.payload['updatedAt'] as int),
                version: Value(remoteOp.payload['version'] as int),
                deleted: Value(_asIntFlag(remoteOp.payload['deleted'])),
                createdAt: Value(remoteOp.payload['createdAt'] as int),
                fieldUpdatedAt: Value(
                  jsonEncode(_parseFieldTimestamps(remoteOp.payload['fieldUpdatedAt'])),
                ),
              ),
              mode: InsertMode.insertOrReplace,
            );
      },
      onUpdate: () async {
        await (_db.update(_db.feedbackMessages)
              ..where((m) => m.id.equals(remoteOp.entityId)))
            .write(
          FeedbackMessagesCompanion(
            threadId: Value(remoteOp.payload['threadId'] as String),
            userId: Value(remoteOp.payload['userId'] as String),
            message: Value(remoteOp.payload['message'] as String),
            senderType: Value(remoteOp.payload['senderType'] as String? ?? 'user'),
            hasAttachments: Value(remoteOp.payload['hasAttachments'] as int? ?? 0),
            updatedAt: Value(remoteOp.payload['updatedAt'] as int),
            version: Value(remoteOp.payload['version'] as int),
            deleted: Value(_asIntFlag(remoteOp.payload['deleted'])),
            fieldUpdatedAt: Value(
              jsonEncode(remoteOp.payload['fieldUpdatedAt'] ?? {}),
            ),
          ),
        );
      },
    );
  }

  Future<bool> _applyFeedbackAttachmentOperation(OplogEntry remoteOp) async {
    final local = await (_db.select(_db.feedbackAttachments)
          ..where((a) => a.id.equals(remoteOp.entityId)))
        .getSingleOrNull();
    return _applyGeneric(
      localVersion: local?.version,
      localUpdatedAt: local?.updatedAt,
      localIsDeleted: local != null && local.deleted == 1,
      remoteOp: remoteOp,
      onInsert: () async {
        await _db.into(_db.feedbackAttachments).insert(
              FeedbackAttachmentsCompanion(
                id: Value(remoteOp.payload['id'] as String),
                messageId: Value(remoteOp.payload['messageId'] as String),
                url: Value(remoteOp.payload['url'] as String),
                type: Value(remoteOp.payload['type'] as String? ?? 'file'),
                size: Value(remoteOp.payload['size'] as int? ?? 0),
                fileName: Value(remoteOp.payload['fileName'] as String?),
                updatedAt: Value(remoteOp.payload['updatedAt'] as int),
                version: Value(remoteOp.payload['version'] as int),
                deleted: Value(_asIntFlag(remoteOp.payload['deleted'])),
                createdAt: Value(remoteOp.payload['createdAt'] as int),
                fieldUpdatedAt: Value(
                  jsonEncode(_parseFieldTimestamps(remoteOp.payload['fieldUpdatedAt'])),
                ),
              ),
              mode: InsertMode.insertOrReplace,
            );
      },
      onUpdate: () async {
        await (_db.update(_db.feedbackAttachments)
              ..where((a) => a.id.equals(remoteOp.entityId)))
            .write(
          FeedbackAttachmentsCompanion(
            messageId: Value(remoteOp.payload['messageId'] as String),
            url: Value(remoteOp.payload['url'] as String),
            type: Value(remoteOp.payload['type'] as String? ?? 'file'),
            size: Value(remoteOp.payload['size'] as int? ?? 0),
            fileName: Value(remoteOp.payload['fileName'] as String?),
            updatedAt: Value(remoteOp.payload['updatedAt'] as int),
            version: Value(remoteOp.payload['version'] as int),
            deleted: Value(_asIntFlag(remoteOp.payload['deleted'])),
            fieldUpdatedAt: Value(
              jsonEncode(remoteOp.payload['fieldUpdatedAt'] ?? {}),
            ),
          ),
        );
      },
    );
  }

  Future<bool> _applyBibleReferenceHistoryOperation(OplogEntry remoteOp) async {
    final local = await (_db.select(_db.bibleReferenceHistory)
          ..where((h) => h.id.equals(remoteOp.entityId)))
        .getSingleOrNull();
    return _applyGeneric(
      localVersion: local?.version,
      localUpdatedAt: local?.updatedAt,
      localIsDeleted: local != null && local.deleted == 1,
      remoteOp: remoteOp,
      onInsert: () async {
        await _db.into(_db.bibleReferenceHistory).insert(
              BibleReferenceHistoryCompanion(
                id: Value(remoteOp.payload['id'] as String),
                userId: Value(remoteOp.payload['userId'] as String),
                book: Value(remoteOp.payload['book'] as String),
                chapter: Value(remoteOp.payload['chapter'] as int),
                verseStart: Value(remoteOp.payload['verseStart'] as int?),
                verseEnd: Value(remoteOp.payload['verseEnd'] as int?),
                translation: Value(remoteOp.payload['translation'] as String),
                openedAt: Value(remoteOp.payload['openedAt'] as int),
                updatedAt: Value(remoteOp.payload['updatedAt'] as int),
                version: Value(remoteOp.payload['version'] as int),
                deleted: Value(_asIntFlag(remoteOp.payload['deleted'])),
                createdAt: Value(remoteOp.payload['createdAt'] as int),
              ),
              mode: InsertMode.insertOrReplace,
            );
      },
      onUpdate: () async {
        await (_db.update(_db.bibleReferenceHistory)
              ..where((h) => h.id.equals(remoteOp.entityId)))
            .write(
          BibleReferenceHistoryCompanion(
            userId: Value(remoteOp.payload['userId'] as String),
            book: Value(remoteOp.payload['book'] as String),
            chapter: Value(remoteOp.payload['chapter'] as int),
            verseStart: Value(remoteOp.payload['verseStart'] as int?),
            verseEnd: Value(remoteOp.payload['verseEnd'] as int?),
            translation: Value(remoteOp.payload['translation'] as String),
            openedAt: Value(remoteOp.payload['openedAt'] as int),
            updatedAt: Value(remoteOp.payload['updatedAt'] as int),
            version: Value(remoteOp.payload['version'] as int),
            deleted: Value(_asIntFlag(remoteOp.payload['deleted'])),
          ),
        );
      },
    );
  }

  Future<bool> _applyHabitLogOperation(OplogEntry remoteOp) async {
    final local = await (_db.select(_db.habitLogs)
          ..where((h) => h.id.equals(remoteOp.entityId)))
        .getSingleOrNull();
    return _applyGeneric(
      localVersion: local?.version,
      localUpdatedAt: local?.updatedAt,
      localIsDeleted: local != null && local.deleted == 1,
      remoteOp: remoteOp,
      onInsert: () async {
        await _db.into(_db.habitLogs).insert(
              HabitLogsCompanion(
                id: Value(remoteOp.payload['id'] as String),
                userId: Value(remoteOp.payload['userId'] as String),
                habitType: Value(remoteOp.payload['habitType'] as String),
                dateDay: Value(remoteOp.payload['dateDay'] as int),
                createdAt: Value(remoteOp.payload['createdAt'] as int),
                updatedAt: Value(remoteOp.payload['updatedAt'] as int),
                version: Value(remoteOp.payload['version'] as int),
                deleted: Value(_asIntFlag(remoteOp.payload['deleted'])),
              ),
              mode: InsertMode.insertOrReplace,
            );
      },
      onUpdate: () async {
        await (_db.update(_db.habitLogs)
              ..where((h) => h.id.equals(remoteOp.entityId)))
            .write(
          HabitLogsCompanion(
            userId: Value(remoteOp.payload['userId'] as String),
            habitType: Value(remoteOp.payload['habitType'] as String),
            dateDay: Value(remoteOp.payload['dateDay'] as int),
            updatedAt: Value(remoteOp.payload['updatedAt'] as int),
            version: Value(remoteOp.payload['version'] as int),
            deleted: Value(_asIntFlag(remoteOp.payload['deleted'])),
          ),
        );
      },
    );
  }

  Future<bool> _applyGeneric({
    required int? localVersion,
    required int? localUpdatedAt,
    required bool localIsDeleted,
    required OplogEntry remoteOp,
    required Future<void> Function() onInsert,
    required Future<void> Function() onUpdate,
  }) async {
    if (localVersion == null || localUpdatedAt == null) {
      if (remoteOp.operation != OplogOperation.delete) {
        await onInsert();
      }
      return false;
    }

    final resolution = _resolveGenericConflict(
      localVersion: localVersion,
      localUpdatedAt: localUpdatedAt,
      localIsDeleted: localIsDeleted,
      remoteVersion: remoteOp.entityVersion,
      remoteUpdatedAt: remoteOp.payload['updatedAt'] as int,
      remoteIsDelete: remoteOp.operation == OplogOperation.delete,
      localDeviceId: _localDeviceId,
      remoteDeviceId: remoteOp.deviceId,
    );

    if (resolution.useRemote) {
      await onUpdate();
    }

    return resolution.hadConflict;
  }

  _GenericResolution _resolveGenericConflict({
    required int localVersion,
    required int localUpdatedAt,
    required bool localIsDeleted,
    required int remoteVersion,
    required int remoteUpdatedAt,
    required bool remoteIsDelete,
    String? localDeviceId,
    String? remoteDeviceId,
  }) {
    // No conflict — remote is strictly newer
    if (remoteVersion > localVersion) {
      return const _GenericResolution(useRemote: true, hadConflict: false);
    }

    // Conflict — apply resolution matrix
    // Rule 1: Delete wins (same as primary entities)
    if (remoteIsDelete || localIsDeleted) {
      if (remoteIsDelete) {
        return const _GenericResolution(useRemote: true, hadConflict: true);
      }
      return const _GenericResolution(useRemote: false, hadConflict: true);
    }

    // Rule 2: Higher updatedAt wins
    if (remoteUpdatedAt > localUpdatedAt) {
      return const _GenericResolution(useRemote: true, hadConflict: true);
    }
    if (remoteUpdatedAt < localUpdatedAt) {
      return const _GenericResolution(useRemote: false, hadConflict: true);
    }

    // Rule 3: Same timestamp — higher version wins
    if (remoteVersion > localVersion) {
      return const _GenericResolution(useRemote: true, hadConflict: true);
    }
    if (remoteVersion < localVersion) {
      return const _GenericResolution(useRemote: false, hadConflict: true);
    }

    // Tie — deterministic tiebreaker using device ID comparison
    if (localDeviceId != null &&
        remoteDeviceId != null &&
        localDeviceId != remoteDeviceId) {
      final remoteWins = remoteDeviceId.compareTo(localDeviceId) > 0;
      return _GenericResolution(useRemote: remoteWins, hadConflict: true);
    }

    // Fallback — local wins by default
    return const _GenericResolution(useRemote: false, hadConflict: true);
  }

  /// Maximum number of times a push or pull request will be retried after a
  /// 429 rate-limit response within a single sync cycle.
  static const _maxRateLimitRetries = 3;

  /// Pause execution after receiving a 429 response.
  ///
  /// Uses [SyncApiException.retryAfter] when available (populated from the
  /// server's `Retry-After` header). Falls back to 30s, capped at 60s.
  Future<void> _awaitRateLimit(SyncApiException e, String phase) async {
    final waitSeconds = (e.retryAfter ?? 30).clamp(1, 60);
    SyncLogger.warning(
      'Rate limited during $phase — waiting ${waitSeconds}s before retry '
      '(retryAfter=${e.retryAfter})',
    );
    await Future.delayed(Duration(seconds: waitSeconds));
  }

  /// Whether a push error is permanent and the failing ops should be
  /// quarantined rather than retried. 4xx errors (client errors) are
  /// generally permanent, except 401 (auth — handled by token refresh)
  /// and 429 (rate limit — transient).
  ///
  /// Also treats per-operation error codes (e.g. NOT_FOUND inside a 200
  /// batch response) as permanent — the server rejected the individual
  /// operation, so retrying it will never succeed.
  bool _isPermanentPushError(SyncApiException e) {
    // Per-operation error codes that the server returns inside a 200 batch
    // response. These indicate the operation itself is invalid and will
    // never succeed on retry.
    const permanentErrorCodes = {
      'NOT_FOUND',
      'FORBIDDEN',
      'VALIDATION_ERROR',
      // Quarantine so the pull phase downloads the server's current version;
      // the user can re-edit on top of that.
      'VERSION_CONFLICT',
    };
    if (permanentErrorCodes.contains(e.code)) return true;

    final statusCode = e.statusCode;
    if (statusCode == null) return false;
    return statusCode >= 400 && statusCode < 500 && statusCode != 401 && statusCode != 429;
  }

  int _asIntFlag(dynamic value) {
    if (value is bool) return value ? 1 : 0;
    if (value is num) return value == 0 ? 0 : 1;
    return 0;
  }

  /// Parse fieldUpdatedAt from various representations (JSON string, Map, null).
  Map<String, int> _parseFieldTimestamps(dynamic value) {
    if (value == null) return {};
    if (value is Map<String, dynamic>) {
      try {
        return value.map((k, v) => MapEntry(k, (v as num).toInt()));
      } catch (_) {
        return {};
      }
    }
    if (value is String) {
      try {
        final decoded = jsonDecode(value) as Map<String, dynamic>;
        return decoded.map((k, v) => MapEntry(k, (v as num).toInt()));
      } catch (_) {
        return {};
      }
    }
    return {};
  }

  /// Schedule a retry with exponential backoff
  void _scheduleRetry() {
    _retryTimer?.cancel();
    final delay = _backoffConfig.getDelay(_consecutiveFailures);

    _retryTimer = Timer(delay, () {
      if (!isSyncing) {
        sync();
      }
    });
  }

  /// Update sync status in database
  Future<void> _updateSyncStatus(String status, {String? error}) async {
    await _db.updateSyncState(
      SyncStateCompanion(
        syncStatus: Value(status),
        lastError: Value(error),
        consecutiveFailures: Value(_consecutiveFailures),
        lastSyncAttempt: Value(TestClock.now()),
        pendingOpsCount: Value(await _db.getPendingOpsCount()),
      ),
    );
  }

  /// Set state and log
  void _setState(SyncEngineState newState) {
    _state = newState;
  }

  /// Emit progress update
  void _emitProgress(SyncProgress progress) {
    _progressController.add(progress);
  }

  /// Convert database oplog row to OplogEntry using a pre-decoded payload.
  ///
  /// The payload JSON is decoded off the main isolate via [compute] in
  /// [_executePushPhase], so this method only constructs the entry.
  OplogEntry? _oplogDataToEntryWithPayload(
    OplogData row,
    Map<String, dynamic> payload,
  ) {
    try {
      return OplogEntry(
        opId: row.opId,
        entityType: OplogEntityType.fromDbValue(row.entityType),
        entityId: row.entityId,
        operation: OplogOperation.fromDbValue(row.operation),
        payload: payload,
        timestamp: row.timestamp,
        deviceId: row.deviceId,
        entityVersion: row.entityVersion,
        synced: row.synced == 1,
        serverTimestamp: row.serverTimestamp,
      );
    } catch (e, stackTrace) {
      SyncLogger.error(
        'Corrupt oplog entry skipped (opId: ${row.opId}, '
        'entity: ${row.entityType}/${row.entityId})',
        e,
        stackTrace,
      );
      return null;
    }
  }

  /// Purge old synced oplog entries and soft-deleted records.
  /// Runs after each successful sync to prevent unbounded database growth.
  Future<void> _performGarbageCollection() async {
    try {
      final result = await _db.purgeOldData();
      if (result.hadWork) {
        SyncLogger.info(
          'Garbage collection: purged ${result.oplogEntriesPurged} oplog entries, '
          '${result.entitiesPurged} deleted entities',
        );
      }
    } catch (e) {
      // GC failure is non-critical — log and continue
      SyncLogger.warning('Garbage collection failed: $e');
    }
  }

  // ==================== Public API ====================

  /// Trigger sync when connectivity is restored. A new network is a fresh
  /// chance to recover from a degraded state, so we clear the failure
  /// counter before attempting.
  void onConnectivityRestored() {
    if (_state == SyncEngineState.degraded) {
      SyncLogger.info(
        'Connectivity restored — clearing degraded state and retrying',
      );
      _consecutiveFailures = 0;
      _setState(SyncEngineState.idle);
      sync();
      return;
    }
    if (_state == SyncEngineState.offline) {
      sync();
    }
  }

  /// Handle connectivity lost
  void onConnectivityLost() {
    _setState(SyncEngineState.offline);
  }

  /// Trigger sync when app resumes
  void onAppResumed() {
    if (!isSyncing) {
      sync();
    }
  }

  /// Handle WebSocket event
  void onWebSocketEvent() {
    // Per spec section 8:
    // Client never trusts payload directly – it always re-applies via sync engine
    if (!isSyncing) {
      sync();
    }
  }

  /// Force sync now (user initiated). Explicit user action clears the
  /// degraded state and resets the failure counter so the request gets a
  /// real attempt instead of being suppressed.
  Future<SyncResult> syncNow() {
    if (_state == SyncEngineState.degraded) {
      SyncLogger.info('Manual sync clearing degraded state');
      _consecutiveFailures = 0;
      _setState(SyncEngineState.idle);
    }
    return sync();
  }

  /// Reset the remote cursor and perform a full snapshot pull.
  ///
  /// Use when a note exists on the server but never arrived via incremental
  /// pull (e.g. direct DB insert with no oplog entry, or after data loss).
  Future<SyncResult> resetAndSync() async {
    await _db.updateSyncState(
      const SyncStateCompanion(lastRemoteCursor: Value(null)),
    );
    return sync();
  }

  /// Get current pending operations count
  Future<int> getPendingOpsCount() => _db.getPendingOpsCount();
}

// ==================== Internal Result Classes ====================

class _PushResult {
  final int operationsPushed;

  const _PushResult({required this.operationsPushed});
}

class _PullResult {
  final int operationsPulled;
  final int conflictsResolved;

  const _PullResult({
    required this.operationsPulled,
    required this.conflictsResolved,
  });
}

class _ApplyResult {
  final bool hadConflict;

  const _ApplyResult({required this.hadConflict});
}

class _GenericResolution {
  final bool useRemote;
  final bool hadConflict;

  const _GenericResolution({
    required this.useRemote,
    required this.hadConflict,
  });
}
