import 'dart:convert';

/// Per-field update timestamps, used for field-level merge on sync.
///
/// When two devices change the same record, comparing one `updatedAt` per
/// record can only pick a whole winner — the later edit replaces the earlier
/// one outright, including fields it never touched. Recording when each field
/// last changed lets the merge keep both: whoever edited a given field most
/// recently wins that field alone.
///
/// This only helps for records with several independently-edited fields. For a
/// junction row, an append-only log, or a record with a single field, per-field
/// timestamps carry no more information than `updatedAt` already does, which is
/// why not every model has them.
///
/// Note that it narrows conflicts rather than removing them: two devices
/// editing the *same* field still need a winner, and the loser's text is still
/// discarded. What guarantees that no edit disappears without trace is the
/// sync engine quarantining anything it cannot merge.
Map<String, int> parseFieldTimestamps(dynamic value) {
  if (value == null) return const {};

  if (value is Map) {
    try {
      return value.map((k, v) => MapEntry(k as String, (v as num).toInt()));
    } catch (_) {
      return const {};
    }
  }

  // Drift stores the map as a JSON string column.
  if (value is String) {
    if (value.isEmpty) return const {};
    try {
      final decoded = jsonDecode(value) as Map<String, dynamic>;
      return decoded.map((k, v) => MapEntry(k, (v as num).toInt()));
    } catch (_) {
      return const {};
    }
  }

  return const {};
}
