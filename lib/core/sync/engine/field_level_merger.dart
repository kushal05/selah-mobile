import 'dart:math';

import '../utils/sync_logger.dart';
import 'sync_clock.dart';

/// Result of a field-level merge operation.
class FieldMergeResult {
  /// Merged field values keyed by field name.
  final Map<String, dynamic> mergedFields;

  /// Merged per-field timestamps (max of both sides per field).
  final Map<String, int> mergedFieldTimestamps;

  /// Merged entity-level updatedAt (max of both sides).
  final int mergedUpdatedAt;

  /// Merged version (max of both sides).
  final int mergedVersion;

  /// Which side won each field: field name → 'local' | 'remote'.
  final Map<String, String> fieldResolutions;

  const FieldMergeResult({
    required this.mergedFields,
    required this.mergedFieldTimestamps,
    required this.mergedUpdatedAt,
    required this.mergedVersion,
    required this.fieldResolutions,
  });
}

/// Deterministic field-level merger for sync conflict resolution.
///
/// Instead of replacing an entire entity when a conflict is detected,
/// this merger compares per-field timestamps and picks the most recent
/// value for each field independently. Both devices running this
/// algorithm arrive at the same state without creating new oplog entries.
class FieldLevelMerger {
  /// How far ahead of now a timestamp may sit before it is read as a wrong
  /// clock rather than a genuinely later write.
  ///
  /// A timestamp is always stamped in the writing device's past, so anything
  /// in the future is skew by definition; five minutes is slack for the jitter
  /// of a device between NTP corrections, and far below the hours-to-years
  /// that a deliberately or accidentally wrong clock produces.
  static const int maxSkewMs = 5 * 60 * 1000;

  /// Merge two versions of an entity field-by-field.
  ///
  /// For each field in [mergeableFieldNames]:
  ///   - Compare timestamps from [localFieldTimestamps] / [remoteFieldTimestamps]
  ///   - Fall back to entity-level [localUpdatedAt] / [remoteUpdatedAt]
  ///   - On timestamp tie, use deterministic device-ID tiebreaker
  ///
  /// Timestamps more than [maxSkewMs] ahead of [now] are replaced by [now] —
  /// the time we observed them — before any of that; the note at the foot of
  /// this file says what that does and does not fix. [now] defaults to
  /// [SyncClock.now]; pass it to make a test's clocks explicit.
  ///
  /// Returns a [FieldMergeResult] containing the merged field values,
  /// merged timestamps, and per-field resolution log.
  FieldMergeResult merge({
    required Map<String, dynamic> localFields,
    required Map<String, int> localFieldTimestamps,
    required int localUpdatedAt,
    required int localVersion,
    required Map<String, dynamic> remoteFields,
    required Map<String, int> remoteFieldTimestamps,
    required int remoteUpdatedAt,
    required int remoteVersion,
    required String localDeviceId,
    required String remoteDeviceId,
    required List<String> mergeableFieldNames,
    int? now,
  }) {
    final mergedFields = <String, dynamic>{};
    final mergedFieldTimestamps = <String, int>{};
    final fieldResolutions = <String, String>{};

    final observedAt = now ?? SyncClock.now();
    var sawSkew = false;

    /// A timestamp implausibly far in the future is replaced by the time we
    /// noticed it, which is the last moment it can honestly claim.
    int trusted(int ts) {
      if (ts <= observedAt + maxSkewMs) return ts;
      sawSkew = true;
      return observedAt;
    }

    for (final field in mergeableFieldNames) {
      final localTime = trusted(localFieldTimestamps[field] ?? localUpdatedAt);
      final remoteTime =
          trusted(remoteFieldTimestamps[field] ?? remoteUpdatedAt);

      final bool useRemote;
      if (remoteTime > localTime) {
        useRemote = true;
      } else if (localTime > remoteTime) {
        useRemote = false;
      } else {
        // Deterministic tiebreaker: higher device ID wins
        useRemote = remoteDeviceId.compareTo(localDeviceId) > 0;
      }

      if (useRemote) {
        mergedFields[field] = remoteFields[field];
        fieldResolutions[field] = 'remote';
      } else {
        mergedFields[field] = localFields[field];
        fieldResolutions[field] = 'local';
      }

      mergedFieldTimestamps[field] = max(localTime, remoteTime);
    }

    // The bounded values, not the raw ones. Writing a future timestamp back
    // would carry the skew into the row and poison every later merge of it;
    // writing the bounded one repairs the row as it passes through.
    final mergedUpdatedAt = max(trusted(localUpdatedAt), trusted(remoteUpdatedAt));
    final mergedVersion = max(localVersion, remoteVersion);

    SyncLogger.info(
      'Field-level merge: $fieldResolutions '
      '(v$localVersion@$localUpdatedAt vs v$remoteVersion@$remoteUpdatedAt '
      '→ v$mergedVersion@$mergedUpdatedAt)'
      '${sawSkew ? ' [clock skew bounded to $observedAt]' : ''}',
    );

    return FieldMergeResult(
      mergedFields: mergedFields,
      mergedFieldTimestamps: mergedFieldTimestamps,
      mergedUpdatedAt: mergedUpdatedAt,
      mergedVersion: mergedVersion,
      fieldResolutions: fieldResolutions,
    );
  }
}

// ─── On bounding clock skew ───────────────────────────────────────────────────
//
// What the bound fixes: a device whose clock runs far ahead used to win every
// field of every merge, permanently, because its timestamps were larger than
// anything a correctly-clocked device could ever produce. Now its writes
// compete as if they had happened when they arrived, so the next real edit from
// any device beats them.
//
// What it does not fix, and cannot: a clock that runs *behind*. Those
// timestamps are in the past, and a write in the past is exactly what a stale
// write looks like — there is nothing in the value to tell the two apart. A
// device hours behind still loses merges it should win. Only server-assigned
// resolution fixes that.
//
// Rejected: reject the skewed side outright rather than bound it. That trades
// a device that wins too much for a device whose edits vanish silently, which
// is the worse failure — a user can undo an overwrite, not a deletion they
// never saw.
//
// Rejected: stamp every write with SyncClock rather than the device clock, so
// skew never enters a timestamp. It is the better fix for sync and the wrong
// one for the app: the same clock dates notes, closes habit streaks and fires
// reminders, and a user whose phone says Tuesday should not have the app say
// Wednesday.
//
// Residual: two devices bound against their own estimate of server time, so
// they agree only to within the error of that estimate — a fraction of a
// second. A timestamp landing inside that window of the threshold could be
// bounded on one device and not the other, and the two would briefly disagree.
// This only arises for timestamps that are already future-dated, i.e. already
// broken; correctly-clocked devices never reach the branch, and their merges
// behave exactly as they did before.
