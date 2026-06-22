import 'dart:math';

import '../utils/sync_logger.dart';

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
  /// Merge two versions of an entity field-by-field.
  ///
  /// For each field in [mergeableFieldNames]:
  ///   - Compare timestamps from [localFieldTimestamps] / [remoteFieldTimestamps]
  ///   - Fall back to entity-level [localUpdatedAt] / [remoteUpdatedAt]
  ///   - On timestamp tie, use deterministic device-ID tiebreaker
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
  }) {
    final mergedFields = <String, dynamic>{};
    final mergedFieldTimestamps = <String, int>{};
    final fieldResolutions = <String, String>{};

    for (final field in mergeableFieldNames) {
      final localTime = localFieldTimestamps[field] ?? localUpdatedAt;
      final remoteTime = remoteFieldTimestamps[field] ?? remoteUpdatedAt;

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

    final mergedUpdatedAt = max(localUpdatedAt, remoteUpdatedAt);
    final mergedVersion = max(localVersion, remoteVersion);

    SyncLogger.info(
      'Field-level merge: $fieldResolutions '
      '(v$localVersion@$localUpdatedAt vs v$remoteVersion@$remoteUpdatedAt '
      '→ v$mergedVersion@$mergedUpdatedAt)',
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
