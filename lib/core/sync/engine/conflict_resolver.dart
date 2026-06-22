/// Conflict resolution logic
///
/// Per spec section 7:
/// Conflict Detection:
/// - Conflict exists if same entity_id AND incoming version <= local version
///
/// Resolution Matrix:
/// | Scenario         | Resolution          |
/// | ---------------- | ------------------- |
/// | Update vs Update | Higher updatedAt    |
/// | Same timestamp   | Higher version      |
/// | Delete vs Update | Delete wins         |
/// | Folder deleted   | All children hidden |
/// | Block conflict   | Last writer wins    |
///
/// ⚠️ Never auto-merge rich text
library;

import '../utils/sync_logger.dart';

/// Result of conflict resolution
class ConflictResolutionResult {
  /// Whether to use the remote version
  final bool useRemote;

  /// Whether a conflict was detected
  final bool hadConflict;

  /// Reason for the resolution
  final String reason;

  const ConflictResolutionResult({
    required this.useRemote,
    required this.hadConflict,
    required this.reason,
  });

  factory ConflictResolutionResult.noConflict({required bool useRemote}) {
    return ConflictResolutionResult(
      useRemote: useRemote,
      hadConflict: false,
      reason: 'No conflict detected',
    );
  }

  factory ConflictResolutionResult.remoteNewer() {
    return const ConflictResolutionResult(
      useRemote: true,
      hadConflict: true,
      reason: 'Remote has higher updatedAt',
    );
  }

  factory ConflictResolutionResult.localNewer() {
    return const ConflictResolutionResult(
      useRemote: false,
      hadConflict: true,
      reason: 'Local has higher updatedAt',
    );
  }

  factory ConflictResolutionResult.remoteHigherVersion() {
    return const ConflictResolutionResult(
      useRemote: true,
      hadConflict: true,
      reason: 'Remote has higher version (same timestamp)',
    );
  }

  factory ConflictResolutionResult.localHigherVersion() {
    return const ConflictResolutionResult(
      useRemote: false,
      hadConflict: true,
      reason: 'Local has higher version (same timestamp)',
    );
  }

  factory ConflictResolutionResult.deleteWins() {
    return const ConflictResolutionResult(
      useRemote: true,
      hadConflict: true,
      reason: 'Delete operation wins',
    );
  }

  factory ConflictResolutionResult.localDeleteWins() {
    return const ConflictResolutionResult(
      useRemote: false,
      hadConflict: true,
      reason: 'Local delete wins over remote update',
    );
  }

  factory ConflictResolutionResult.localDefault() {
    return const ConflictResolutionResult(
      useRemote: false,
      hadConflict: true,
      reason: 'Local wins by default (same timestamp and version)',
    );
  }

  factory ConflictResolutionResult.deterministicTiebreaker({
    required bool useRemote,
  }) {
    return ConflictResolutionResult(
      useRemote: useRemote,
      hadConflict: true,
      reason: useRemote
          ? 'Remote wins by deterministic deviceId tiebreaker'
          : 'Local wins by deterministic deviceId tiebreaker',
    );
  }

  @override
  String toString() {
    return 'ConflictResolution(useRemote: $useRemote, '
        'hadConflict: $hadConflict, reason: $reason)';
  }
}

/// Deterministic conflict resolver
///
/// Per spec section 7:
/// All conflict resolution must be deterministic and replayable.
class ConflictResolver {
  /// Resolve folder conflict
  ///
  /// Per spec section 7.2:
  /// - Delete vs Update: Delete wins
  /// - Update vs Update: Higher updatedAt
  /// - Same timestamp: Higher version
  ConflictResolutionResult resolveFolder({
    required String entityId,
    required int localVersion,
    required int localUpdatedAt,
    required int remoteVersion,
    required int remoteUpdatedAt,
    required bool remoteIsDelete,
    required bool localIsDelete,
    String? localDeviceId,
    String? remoteDeviceId,
  }) {
    return _resolve(
      entityType: 'folder',
      entityId: entityId,
      localVersion: localVersion,
      localUpdatedAt: localUpdatedAt,
      remoteVersion: remoteVersion,
      remoteUpdatedAt: remoteUpdatedAt,
      remoteIsDelete: remoteIsDelete,
      localIsDelete: localIsDelete,
      localDeviceId: localDeviceId,
      remoteDeviceId: remoteDeviceId,
    );
  }

  /// Resolve note conflict
  ///
  /// Same rules as folder conflict
  ConflictResolutionResult resolveNote({
    required String entityId,
    required int localVersion,
    required int localUpdatedAt,
    required int remoteVersion,
    required int remoteUpdatedAt,
    required bool remoteIsDelete,
    required bool localIsDelete,
    String? localDeviceId,
    String? remoteDeviceId,
  }) {
    return _resolve(
      entityType: 'note',
      entityId: entityId,
      localVersion: localVersion,
      localUpdatedAt: localUpdatedAt,
      remoteVersion: remoteVersion,
      remoteUpdatedAt: remoteUpdatedAt,
      remoteIsDelete: remoteIsDelete,
      localIsDelete: localIsDelete,
      localDeviceId: localDeviceId,
      remoteDeviceId: remoteDeviceId,
    );
  }

  /// Resolve block conflict
  ///
  /// Per spec section 7.2:
  /// - Block conflict: Last writer wins
  /// - Never auto-merge rich text
  ConflictResolutionResult resolveBlock({
    required String entityId,
    required int localVersion,
    required int localUpdatedAt,
    required int remoteVersion,
    required int remoteUpdatedAt,
    required bool remoteIsDelete,
    required bool localIsDelete,
    String? localDeviceId,
    String? remoteDeviceId,
  }) {
    // Block uses same resolution logic but NEVER merges content
    return _resolve(
      entityType: 'note_block',
      entityId: entityId,
      localVersion: localVersion,
      localUpdatedAt: localUpdatedAt,
      remoteVersion: remoteVersion,
      remoteUpdatedAt: remoteUpdatedAt,
      remoteIsDelete: remoteIsDelete,
      localIsDelete: localIsDelete,
      localDeviceId: localDeviceId,
      remoteDeviceId: remoteDeviceId,
    );
  }

  /// Resolve prayer conflict
  ///
  /// Same rules as folder conflict
  ConflictResolutionResult resolvePrayer({
    required String entityId,
    required int localVersion,
    required int localUpdatedAt,
    required int remoteVersion,
    required int remoteUpdatedAt,
    required bool remoteIsDelete,
    required bool localIsDelete,
    String? localDeviceId,
    String? remoteDeviceId,
  }) {
    return _resolve(
      entityType: 'prayer',
      entityId: entityId,
      localVersion: localVersion,
      localUpdatedAt: localUpdatedAt,
      remoteVersion: remoteVersion,
      remoteUpdatedAt: remoteUpdatedAt,
      remoteIsDelete: remoteIsDelete,
      localIsDelete: localIsDelete,
      localDeviceId: localDeviceId,
      remoteDeviceId: remoteDeviceId,
    );
  }

  /// Resolve promise conflict
  ///
  /// Same rules as folder conflict
  ConflictResolutionResult resolvePromise({
    required String entityId,
    required int localVersion,
    required int localUpdatedAt,
    required int remoteVersion,
    required int remoteUpdatedAt,
    required bool remoteIsDelete,
    required bool localIsDelete,
    String? localDeviceId,
    String? remoteDeviceId,
  }) {
    return _resolve(
      entityType: 'promise',
      entityId: entityId,
      localVersion: localVersion,
      localUpdatedAt: localUpdatedAt,
      remoteVersion: remoteVersion,
      remoteUpdatedAt: remoteUpdatedAt,
      remoteIsDelete: remoteIsDelete,
      localIsDelete: localIsDelete,
      localDeviceId: localDeviceId,
      remoteDeviceId: remoteDeviceId,
    );
  }

  /// Resolve person conflict
  ///
  /// Same rules as folder conflict
  ConflictResolutionResult resolvePerson({
    required String entityId,
    required int localVersion,
    required int localUpdatedAt,
    required int remoteVersion,
    required int remoteUpdatedAt,
    required bool remoteIsDelete,
    required bool localIsDelete,
    String? localDeviceId,
    String? remoteDeviceId,
  }) {
    return _resolve(
      entityType: 'person',
      entityId: entityId,
      localVersion: localVersion,
      localUpdatedAt: localUpdatedAt,
      remoteVersion: remoteVersion,
      remoteUpdatedAt: remoteUpdatedAt,
      remoteIsDelete: remoteIsDelete,
      localIsDelete: localIsDelete,
      localDeviceId: localDeviceId,
      remoteDeviceId: remoteDeviceId,
    );
  }

  /// Resolve song conflict
  ///
  /// Same rules as folder conflict
  ConflictResolutionResult resolveSong({
    required String entityId,
    required int localVersion,
    required int localUpdatedAt,
    required int remoteVersion,
    required int remoteUpdatedAt,
    required bool remoteIsDelete,
    required bool localIsDelete,
    String? localDeviceId,
    String? remoteDeviceId,
  }) {
    return _resolve(
      entityType: 'song',
      entityId: entityId,
      localVersion: localVersion,
      localUpdatedAt: localUpdatedAt,
      remoteVersion: remoteVersion,
      remoteUpdatedAt: remoteUpdatedAt,
      remoteIsDelete: remoteIsDelete,
      localIsDelete: localIsDelete,
      localDeviceId: localDeviceId,
      remoteDeviceId: remoteDeviceId,
    );
  }

  /// Core resolution algorithm
  ///
  /// Per spec section 7.1:
  /// Conflict exists if:
  /// - Same entity_id
  /// - Incoming version <= local version
  ///
  /// Per spec section 7.2 Resolution Matrix:
  /// | Scenario         | Resolution          |
  /// | ---------------- | ------------------- |
  /// | Update vs Update | Higher updatedAt    |
  /// | Same timestamp   | Higher version      |
  /// | Delete vs Update | Delete wins         |
  ConflictResolutionResult _resolve({
    required String entityType,
    required String entityId,
    required int localVersion,
    required int localUpdatedAt,
    required int remoteVersion,
    required int remoteUpdatedAt,
    required bool remoteIsDelete,
    required bool localIsDelete,
    String? localDeviceId,
    String? remoteDeviceId,
  }) {
    // Check if this is a conflict
    // Per spec: Conflict if incoming version <= local version
    final isConflict = remoteVersion <= localVersion;

    if (!isConflict) {
      // No conflict - remote is strictly newer, apply it
      return ConflictResolutionResult.noConflict(useRemote: true);
    }

    // We have a conflict - need to resolve
    ConflictResolutionResult result;

    // Rule 1: Delete always wins regardless of which side performed it
    // Per spec: "Delete vs Update -> Delete wins"
    if (remoteIsDelete || localIsDelete) {
      if (remoteIsDelete) {
        result = ConflictResolutionResult.deleteWins();
      } else {
        // Local is deleted - keep local deletion, reject remote update
        result = ConflictResolutionResult.localDeleteWins();
      }
    }
    // Rule 2: Compare updatedAt timestamps
    // Per spec: "Update vs Update -> Higher updatedAt"
    else if (remoteUpdatedAt > localUpdatedAt) {
      result = ConflictResolutionResult.remoteNewer();
    } else if (remoteUpdatedAt < localUpdatedAt) {
      result = ConflictResolutionResult.localNewer();
    }
    // Rule 3: Same timestamp - compare versions
    // Per spec: "Same timestamp -> Higher version"
    else if (remoteVersion > localVersion) {
      result = ConflictResolutionResult.remoteHigherVersion();
    } else if (remoteVersion < localVersion) {
      result = ConflictResolutionResult.localHigherVersion();
    }
    // Same timestamp AND same version — deterministic tiebreaker.
    // Compare device IDs lexicographically so both devices converge
    // on the same winner. Falls back to local-wins if IDs unavailable.
    else {
      if (localDeviceId != null &&
          remoteDeviceId != null &&
          localDeviceId != remoteDeviceId) {
        final remoteWins = remoteDeviceId.compareTo(localDeviceId) > 0;
        result = ConflictResolutionResult.deterministicTiebreaker(
          useRemote: remoteWins,
        );
      } else {
        result = ConflictResolutionResult.localDefault();
      }
    }

    // Per spec section 11: log all conflict resolutions
    final log = ConflictLog(
      entityType: entityType,
      entityId: entityId,
      localVersion: localVersion,
      remoteVersion: remoteVersion,
      localUpdatedAt: localUpdatedAt,
      remoteUpdatedAt: remoteUpdatedAt,
      resolution: result,
    );
    SyncLogger.info('Conflict resolved: $log');

    return result;
  }
}

/// Logging helper for conflict resolution observability
///
/// Per spec section 11:
/// You MUST log conflict resolutions
class ConflictLog {
  final String entityType;
  final String entityId;
  final int localVersion;
  final int remoteVersion;
  final int localUpdatedAt;
  final int remoteUpdatedAt;
  final ConflictResolutionResult resolution;
  final DateTime timestamp;

  ConflictLog({
    required this.entityType,
    required this.entityId,
    required this.localVersion,
    required this.remoteVersion,
    required this.localUpdatedAt,
    required this.remoteUpdatedAt,
    required this.resolution,
  }) : timestamp = DateTime.now();

  Map<String, dynamic> toJson() {
    return {
      'entityType': entityType,
      'entityId': entityId,
      'localVersion': localVersion,
      'remoteVersion': remoteVersion,
      'localUpdatedAt': localUpdatedAt,
      'remoteUpdatedAt': remoteUpdatedAt,
      'useRemote': resolution.useRemote,
      'reason': resolution.reason,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  @override
  String toString() {
    return 'ConflictLog($entityType/$entityId: '
        'local v$localVersion@$localUpdatedAt vs '
        'remote v$remoteVersion@$remoteUpdatedAt -> '
        '${resolution.useRemote ? "REMOTE" : "LOCAL"} wins: ${resolution.reason})';
  }
}
