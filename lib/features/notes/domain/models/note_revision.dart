import 'dart:convert';

import '../../../../core/sync/models/note_block_model.dart';
import '../../../../core/sync/models/note_model.dart';

/// Domain model for a note revision snapshot.
///
/// Revisions are local-only and never synced. Each revision stores a full
/// JSON snapshot of the note metadata + blocks at a point in time.
class NoteRevisionSnapshot {
  final String id;
  final String noteId;
  final String snapshotJson;
  final DateTime createdAt;

  /// Lazily cached decoded JSON to avoid repeated parsing.
  Map<String, dynamic>? _cachedMap;

  NoteRevisionSnapshot({
    required this.id,
    required this.noteId,
    required this.snapshotJson,
    required this.createdAt,
  });

  Map<String, dynamic>? get _parsedMap {
    if (_cachedMap != null) return _cachedMap;
    try {
      _cachedMap = jsonDecode(snapshotJson) as Map<String, dynamic>;
      return _cachedMap;
    } catch (_) {
      return null;
    }
  }

  /// Decode the snapshot into note + blocks.
  /// Returns null if the snapshot JSON is corrupt.
  ({NoteModel note, List<NoteBlockModel> blocks})? deserialize() {
    try {
      final map = _parsedMap;
      if (map == null) return null;
      final note = NoteModel.fromJson(map['note'] as Map<String, dynamic>);
      final blocks = (map['blocks'] as List? ?? [])
          .map((b) => NoteBlockModel.fromJson(b as Map<String, dynamic>))
          .toList();
      return (note: note, blocks: blocks);
    } catch (_) {
      return null;
    }
  }

  /// Title extracted from the snapshot (for list display).
  String get title {
    try {
      final map = _parsedMap;
      if (map == null) return 'Untitled';
      return (map['note'] as Map<String, dynamic>)['title'] as String? ??
          'Untitled';
    } catch (_) {
      return 'Untitled';
    }
  }

  /// Number of blocks in the snapshot.
  int get blockCount {
    try {
      final map = _parsedMap;
      if (map == null) return 0;
      return (map['blocks'] as List? ?? []).length;
    } catch (_) {
      return 0;
    }
  }
}
