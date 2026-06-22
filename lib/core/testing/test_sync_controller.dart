import 'dart:async';

import '../sync/engine/sync_engine.dart';
import '../sync/engine/sync_state_machine.dart';
import '../sync/services/sync_service.dart';

/// Provides explicit control over the sync engine for integration tests.
///
/// Allows tests to pause, resume, force-push, force-pull, and wait for
/// specific sync states without relying on timers or sleep.
class TestSyncController {
  final SyncService _syncService;

  TestSyncController(this._syncService);

  SyncEngine get _engine => _syncService.engine;

  // ── Pause / Resume ──────────────────────────────────────────────────

  bool _paused = false;

  /// Whether sync is currently paused by this controller.
  bool get isPaused => _paused;

  /// Pause all automatic sync triggers (periodic, oplog, connectivity).
  ///
  /// Manual [forcePush] / [forcePull] still work while paused.
  void pauseSync() {
    _paused = true;
    // Signal the engine that we're "offline" so periodic timers stop firing.
    _engine.onConnectivityLost();
  }

  /// Resume automatic sync triggers.
  void resumeSync() {
    _paused = false;
    _engine.onConnectivityRestored();
  }

  // ── Manual triggers ─────────────────────────────────────────────────

  /// Execute a full push+pull cycle and return the result.
  Future<SyncResult> forceSync() => _engine.sync();

  /// Execute push phase only.
  ///
  /// Calls sync() which does push-then-pull; for a pure push-only
  /// integration test, assert on the result's [operationsPushed].
  Future<SyncResult> forcePush() => _engine.sync();

  /// Execute pull phase only.
  ///
  /// Note: The engine always does push-then-pull. For tests that need
  /// pull-only behavior, ensure no pending oplogs exist before calling.
  Future<SyncResult> forcePull() => _engine.sync();

  // ── Waiters ─────────────────────────────────────────────────────────

  /// Wait until the engine reaches [targetState], or until [timeout].
  Future<void> waitForState(
    SyncEngineState targetState, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    if (_engine.state == targetState) return;

    final completer = Completer<void>();
    late StreamSubscription<SyncProgress> sub;

    sub = _engine.progressStream.listen((progress) {
      if (_engine.state == targetState) {
        sub.cancel();
        if (!completer.isCompleted) completer.complete();
      }
    });

    try {
      await completer.future.timeout(timeout);
    } on TimeoutException {
      sub.cancel();
      throw TimeoutException(
        'SyncEngine did not reach $targetState within $timeout '
        '(current: ${_engine.state})',
      );
    }
  }

  /// Wait until all pending oplogs are synced (count == 0).
  Future<void> waitForEmptyOplog({
    Duration timeout = const Duration(seconds: 15),
    Duration pollInterval = const Duration(milliseconds: 200),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final count = await _syncService.getPendingOpsCount();
      if (count == 0) return;
      await Future<void>.delayed(pollInterval);
    }
    final remaining = await _syncService.getPendingOpsCount();
    throw TimeoutException(
      'Oplog not empty after $timeout ($remaining ops remaining)',
    );
  }
}
