import '../models/oplog_entry.dart';

/// Result of oplog compression.
class CompressedResult {
  /// Entries that should be pushed to the server.
  final List<OplogEntry> entriesToPush;

  /// Op IDs that were absorbed (redundant UPDATE ops merged away).
  /// These should be marked as synced without pushing.
  final List<String> absorbedOpIds;

  const CompressedResult({
    required this.entriesToPush,
    required this.absorbedOpIds,
  });
}

/// Compresses consecutive UPDATE ops for the same entity within a time window.
///
/// Before pushing, multiple rapid UPDATE ops on the same entityId are merged
/// into a single op carrying the latest payload. This reduces bandwidth and
/// server load for burst edits (e.g. typing in a note editor).
///
/// Rules:
/// - Only UPDATE ops are compressible.
/// - INSERT and DELETE ops are never compressed.
/// - UPDATEs are only merged when they share the same entityId AND each
///   consecutive pair is within [_windowMs] milliseconds of each other.
/// - The surviving op is always the latest one in the group (latest payload,
///   version, and timestamp). All earlier ops become absorbed.
class OplogCompressor {
  /// Maximum gap between two UPDATE timestamps to consider them mergeable.
  static const _windowMs = 3000;

  /// Compress a list of [OplogEntry] that is already sorted by timestamp ASC.
  ///
  /// Returns a [CompressedResult] containing the entries to push and the
  /// op IDs that were absorbed.
  static CompressedResult compress(List<OplogEntry> entries) {
    if (entries.length <= 1) {
      return CompressedResult(entriesToPush: entries, absorbedOpIds: const []);
    }

    final entriesToPush = <OplogEntry>[];
    final absorbedOpIds = <String>[];

    // Walk through entries, collecting runs of mergeable UPDATEs.
    // A "run" is a sequence of consecutive UPDATE ops with the same entityId
    // where each pair is within the time window.
    var i = 0;
    while (i < entries.length) {
      final current = entries[i];

      // Non-UPDATE ops are always emitted as-is.
      if (current.operation != OplogOperation.update) {
        entriesToPush.add(current);
        i++;
        continue;
      }

      // Start a run of UPDATE ops for this entityId.
      var runEnd = i;
      while (runEnd + 1 < entries.length) {
        final next = entries[runEnd + 1];
        if (next.operation != OplogOperation.update) break;
        if (next.entityId != current.entityId) break;
        if (next.timestamp - entries[runEnd].timestamp > _windowMs) break;
        runEnd++;
      }

      // Keep only the last entry in the run; absorb the rest.
      for (var j = i; j < runEnd; j++) {
        absorbedOpIds.add(entries[j].opId);
      }
      entriesToPush.add(entries[runEnd]);

      i = runEnd + 1;
    }

    return CompressedResult(
      entriesToPush: entriesToPush,
      absorbedOpIds: absorbedOpIds,
    );
  }
}
