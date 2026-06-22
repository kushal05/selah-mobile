/// Sync engine state machine
///
/// Per spec section 5.1:
/// The sync engine has these responsibilities:
/// 1. Push unsynced oplog entries
/// 2. Pull remote operations
/// 3. Apply remote ops locally
/// 4. Resolve conflicts deterministically
/// 5. Recover from crashes safely
library;

/// Current state of the sync engine
enum SyncEngineState {
  /// Sync engine is idle, not actively syncing
  idle,

  /// Currently pushing local changes to server
  pushing,

  /// Currently pulling remote changes from server
  pulling,

  /// Applying pulled changes locally
  applying,

  /// Sync encountered an error
  error,

  /// Device is offline, sync paused
  offline,

  /// Sync is paused (user initiated)
  paused,

  /// Sync has failed enough times in a row that automated triggers are
  /// suppressed to avoid log spam and battery drain. Cleared by a successful
  /// sync, connectivity change, or explicit user-initiated sync.
  degraded,
}

/// Events that trigger state transitions
enum SyncEvent {
  /// Network connectivity restored
  connectivityRestored,

  /// Network connectivity lost
  connectivityLost,

  /// App resumed from background
  appResumed,

  /// App going to background
  appPaused,

  /// Periodic sync timer fired
  timerFired,

  /// WebSocket event received
  webSocketEvent,

  /// User initiated sync
  userTriggered,

  /// Push completed successfully
  pushCompleted,

  /// Pull completed successfully
  pullCompleted,

  /// Apply completed successfully
  applyCompleted,

  /// Operation failed
  operationFailed,

  /// User paused sync
  userPaused,

  /// User resumed sync
  userResumed,
}

/// Result of a sync operation
class SyncResult {
  final bool success;
  final int operationsPushed;
  final int operationsPulled;
  final int conflictsResolved;
  final String? error;
  final Duration duration;

  const SyncResult({
    required this.success,
    this.operationsPushed = 0,
    this.operationsPulled = 0,
    this.conflictsResolved = 0,
    this.error,
    required this.duration,
  });

  factory SyncResult.success({
    int operationsPushed = 0,
    int operationsPulled = 0,
    int conflictsResolved = 0,
    required Duration duration,
  }) {
    return SyncResult(
      success: true,
      operationsPushed: operationsPushed,
      operationsPulled: operationsPulled,
      conflictsResolved: conflictsResolved,
      duration: duration,
    );
  }

  factory SyncResult.failure(String error, Duration duration) {
    return SyncResult(
      success: false,
      error: error,
      duration: duration,
    );
  }

  @override
  String toString() {
    if (success) {
      return 'SyncResult(success, pushed: $operationsPushed, '
          'pulled: $operationsPulled, conflicts: $conflictsResolved, '
          'duration: ${duration.inMilliseconds}ms)';
    }
    return 'SyncResult(failed: $error, duration: ${duration.inMilliseconds}ms)';
  }
}

/// Sync progress for UI display
class SyncProgress {
  final SyncEngineState state;
  final int pendingOps;
  final int totalOps;
  final String? currentEntity;
  final double percentage;

  /// Per-entity-type operation counts accumulated during the current pull.
  /// Keys are db-style strings (e.g. 'note', 'prayer'). Empty when idle.
  final Map<String, int> entityCounts;

  const SyncProgress({
    required this.state,
    required this.pendingOps,
    required this.totalOps,
    this.currentEntity,
    required this.percentage,
    this.entityCounts = const {},
  });

  factory SyncProgress.idle(int pendingOps) {
    return SyncProgress(
      state: SyncEngineState.idle,
      pendingOps: pendingOps,
      totalOps: pendingOps,
      percentage: 0,
    );
  }

  factory SyncProgress.pushing(int pending, int total, String? entity) {
    return SyncProgress(
      state: SyncEngineState.pushing,
      pendingOps: pending,
      totalOps: total,
      currentEntity: entity,
      percentage: total > 0 ? (total - pending) / total : 0,
    );
  }

  factory SyncProgress.pulling({Map<String, int> counts = const {}}) {
    return SyncProgress(
      state: SyncEngineState.pulling,
      pendingOps: 0,
      totalOps: 0,
      percentage: 0,
      entityCounts: counts,
    );
  }

  factory SyncProgress.applying({Map<String, int> counts = const {}}) {
    return SyncProgress(
      state: SyncEngineState.applying,
      pendingOps: 0,
      totalOps: 0,
      percentage: 0,
      entityCounts: counts,
    );
  }

  factory SyncProgress.offline(int pendingOps) {
    return SyncProgress(
      state: SyncEngineState.offline,
      pendingOps: pendingOps,
      totalOps: pendingOps,
      percentage: 0,
    );
  }

  factory SyncProgress.error(int pendingOps) {
    return SyncProgress(
      state: SyncEngineState.error,
      pendingOps: pendingOps,
      totalOps: pendingOps,
      percentage: 0,
    );
  }

  factory SyncProgress.degraded(int pendingOps) {
    return SyncProgress(
      state: SyncEngineState.degraded,
      pendingOps: pendingOps,
      totalOps: pendingOps,
      percentage: 0,
    );
  }

  bool get isSyncing =>
      state == SyncEngineState.pushing ||
      state == SyncEngineState.pulling ||
      state == SyncEngineState.applying;

  bool get isIdle => state == SyncEngineState.idle;
  bool get isOffline => state == SyncEngineState.offline;
  bool get hasError => state == SyncEngineState.error;
  bool get isDegraded => state == SyncEngineState.degraded;
  bool get hasPendingOps => pendingOps > 0;

  @override
  String toString() {
    return 'SyncProgress(state: $state, pending: $pendingOps/$totalOps, '
        '${(percentage * 100).toStringAsFixed(1)}%, entities: $entityCounts)';
  }
}

/// Backoff configuration for retry logic
class BackoffConfig {
  /// Initial delay after first failure (milliseconds)
  final int initialDelayMs;

  /// Maximum delay between retries (milliseconds)
  final int maxDelayMs;

  /// Multiplier for exponential backoff
  final double multiplier;

  /// Maximum number of retries before giving up
  final int maxRetries;

  const BackoffConfig({
    this.initialDelayMs = 1000,
    this.maxDelayMs = 60000,
    this.multiplier = 2.0,
    this.maxRetries = 5,
  });

  /// Calculate delay for a given attempt number
  Duration getDelay(int attempt) {
    if (attempt <= 0) return Duration.zero;

    var delay = initialDelayMs * (multiplier * (attempt - 1)).toInt();
    delay = delay.clamp(initialDelayMs, maxDelayMs);

    return Duration(milliseconds: delay);
  }

  /// Check if we should retry after given number of attempts
  bool shouldRetry(int attempts) => attempts < maxRetries;
}
