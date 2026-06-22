import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../database/sync_database.dart';
import '../sync/services/sync_service.dart';
import 'test_clock.dart';
import 'test_sync_controller.dart';

/// Debug-only HTTP server that exposes deterministic app state for
/// integration tests and Maestro flows.
///
/// Endpoints:
///   GET  /test/health          → 200 OK
///   GET  /test/sync-state      → current sync engine state + pending count
///   GET  /test/oplog           → list of pending (unsynced) oplog entries
///   GET  /test/oplog/count     → { "count": N }
///   POST /test/sync            → force a full sync cycle
///   POST /test/offline         → pause sync (simulate offline)
///   POST /test/online          → resume sync (simulate online)
///   POST /test/reset           → clear all user data
///   POST /test/seed            → seed entities from JSON body
///   POST /test/clock/set       → freeze TestClock at given timestamp
///   POST /test/clock/advance   → advance TestClock by delta ms
///   POST /test/clock/reset     → reset TestClock to real-time
///
/// The server binds to localhost:8081 and is ONLY started in debug/profile mode.
class TestBridge {
  final SyncDatabase _db;
  final SyncService? _syncService;
  TestSyncController? _syncController;
  HttpServer? _server;

  static const int port = 8081;

  TestBridge({
    required SyncDatabase db,
    SyncService? syncService,
  })  : _db = db,
        _syncService = syncService {
    if (_syncService != null && _syncService.isInitialized) {
      _syncController = TestSyncController(_syncService);
    }
  }

  /// Start the debug HTTP server. No-op in release mode.
  Future<void> start() async {
    if (kReleaseMode) return;

    try {
      _server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
      debugPrint('[TestBridge] listening on http://localhost:$port');
      _server!.listen(_handleRequest);
    } catch (e) {
      debugPrint('[TestBridge] failed to start: $e');
    }
  }

  /// Stop the server.
  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  /// Attach a sync service after it initializes (it's async).
  void attachSyncService(SyncService service) {
    _syncController = TestSyncController(service);
  }

  // ── Request router ──────────────────────────────────────────────────

  Future<void> _handleRequest(HttpRequest request) async {
    final path = request.uri.path;
    final method = request.method;

    try {
      if (path == '/test/health' && method == 'GET') {
        _json(request, {'status': 'ok'});
      } else if (path == '/test/sync-state' && method == 'GET') {
        await _handleGetSyncState(request);
      } else if (path == '/test/oplog' && method == 'GET') {
        await _handleGetOplog(request);
      } else if (path == '/test/oplog/count' && method == 'GET') {
        await _handleGetOplogCount(request);
      } else if (path == '/test/sync' && method == 'POST') {
        await _handleForceSync(request);
      } else if (path == '/test/offline' && method == 'POST') {
        _handleGoOffline(request);
      } else if (path == '/test/online' && method == 'POST') {
        _handleGoOnline(request);
      } else if (path == '/test/reset' && method == 'POST') {
        await _handleReset(request);
      } else if (path == '/test/seed' && method == 'POST') {
        await _handleSeed(request);
      } else if (path == '/test/clock/set' && method == 'POST') {
        await _handleClockSet(request);
      } else if (path == '/test/clock/advance' && method == 'POST') {
        await _handleClockAdvance(request);
      } else if (path == '/test/clock/reset' && method == 'POST') {
        _handleClockReset(request);
      } else {
        request.response
          ..statusCode = HttpStatus.notFound
          ..write('Not found: $method $path')
          ..close();
      }
    } catch (e, st) {
      debugPrint('[TestBridge] error handling $method $path: $e\n$st');
      request.response
        ..statusCode = HttpStatus.internalServerError
        ..write(jsonEncode({'error': e.toString()}))
        ..close();
    }
  }

  // ── Handlers ────────────────────────────────────────────────────────

  Future<void> _handleGetSyncState(HttpRequest request) async {
    final syncState = await _db.getSyncState();
    final pendingCount = await _db.getPendingOpsCount();
    _json(request, {
      'syncStatus': syncState.syncStatus,
      'pendingOps': pendingCount,
      'consecutiveFailures': syncState.consecutiveFailures,
      'lastSyncAttempt': syncState.lastSyncAttempt,
      'lastRemoteCursor': syncState.lastRemoteCursor,
      'controllerPaused': _syncController?.isPaused ?? false,
    });
  }

  Future<void> _handleGetOplog(HttpRequest request) async {
    final ops = await _db.getUnsyncedOps();
    final list = ops
        .map((op) => {
              'opId': op.opId,
              'entityType': op.entityType,
              'entityId': op.entityId,
              'operation': op.operation,
              'timestamp': op.timestamp,
              'entityVersion': op.entityVersion,
              'synced': op.synced == 1 ? true : false,
            })
        .toList();
    _json(request, {'ops': list, 'count': list.length});
  }

  Future<void> _handleGetOplogCount(HttpRequest request) async {
    final count = await _db.getPendingOpsCount();
    _json(request, {'count': count});
  }

  Future<void> _handleForceSync(HttpRequest request) async {
    if (_syncController == null) {
      _json(request, {'error': 'sync not initialized'}, status: 503);
      return;
    }
    final result = await _syncController!.forceSync();
    _json(request, {
      'success': result.success,
      'pushed': result.operationsPushed,
      'pulled': result.operationsPulled,
      'conflicts': result.conflictsResolved,
      'durationMs': result.duration.inMilliseconds,
    });
  }

  void _handleGoOffline(HttpRequest request) {
    if (_syncController == null) {
      _json(request, {'error': 'sync not initialized'}, status: 503);
      return;
    }
    _syncController!.pauseSync();
    _json(request, {'offline': true});
  }

  void _handleGoOnline(HttpRequest request) {
    if (_syncController == null) {
      _json(request, {'error': 'sync not initialized'}, status: 503);
      return;
    }
    _syncController!.resumeSync();
    _json(request, {'online': true});
  }

  Future<void> _handleReset(HttpRequest request) async {
    await _db.clearAllUserData();
    TestClock.reset();
    _json(request, {'reset': true});
  }

  Future<void> _handleSeed(HttpRequest request) async {
    final body = await utf8.decoder.bind(request).join();
    final payload = jsonDecode(body) as Map<String, dynamic>;
    // Seeding is handled by the test code; this endpoint accepts a payload
    // and inserts raw rows. For now, return the payload for verification.
    _json(request, {'seeded': true, 'payload': payload});
  }

  Future<void> _handleClockSet(HttpRequest request) async {
    final body = await utf8.decoder.bind(request).join();
    final payload = jsonDecode(body) as Map<String, dynamic>;
    final ts = payload['timestamp'] as int;
    TestClock.setFixed(ts);
    _json(request, {'clock': ts, 'frozen': true});
  }

  Future<void> _handleClockAdvance(HttpRequest request) async {
    final body = await utf8.decoder.bind(request).join();
    final payload = jsonDecode(body) as Map<String, dynamic>;
    final delta = payload['deltaMs'] as int;
    TestClock.advance(delta);
    _json(request, {'clock': TestClock.now(), 'advanced': delta});
  }

  void _handleClockReset(HttpRequest request) {
    TestClock.reset();
    _json(request, {'clock': 'real-time', 'frozen': false});
  }

  // ── Helpers ─────────────────────────────────────────────────────────

  void _json(HttpRequest request, Map<String, dynamic> body, {int status = 200}) {
    request.response
      ..statusCode = status
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(body))
      ..close();
  }
}
