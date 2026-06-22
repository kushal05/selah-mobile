import 'package:drift/drift.dart';

import '../../../../core/database/services/note_block_fts_service.dart';
import '../../../../core/database/sync_database.dart';

/// One note that links back to the note we're viewing.
class Backlink {
  final String noteId;
  final String noteTitle;
  final String snippet;
  final int updatedAt;

  const Backlink({
    required this.noteId,
    required this.noteTitle,
    required this.snippet,
    required this.updatedAt,
  });
}

/// Finds other notes that mention the current note. Matching strategy:
///   1. FTS phrase search on the note's title (skipping titles that are too
///      short or generic to produce useful hits).
///   2. Substring search on the note's ID for wiki-link patterns
///      `[[<noteId>]]` that some power users adopt.
/// Self-references (blocks belonging to the source note) are always excluded.
class NoteBacklinksService {
  final SyncDatabase _db;
  final NoteBlockFtsService _fts;

  NoteBacklinksService(this._db, this._fts);

  /// Minimum title length to use as an FTS phrase. Below this, the match
  /// produces too many false positives (e.g. a note titled "God").
  static const _minTitleLengthForFts = 4;

  Future<List<Backlink>> findBacklinks({
    required String noteId,
    required String userId,
    int limit = 50,
  }) async {
    // Load the source note's title once.
    final source = await (_db.select(_db.syncNotes)
          ..where((n) => n.id.equals(noteId)))
        .getSingleOrNull();
    if (source == null) return const [];

    final perNote = <String, Backlink>{};

    // 1) FTS title search — phrase form so words must appear together.
    if (source.title.trim().length >= _minTitleLengthForFts) {
      final phraseQuery = '"${source.title.replaceAll('"', '')}"';
      final hits = await _fts.search(phraseQuery, limit: limit * 2);
      for (final hit in hits) {
        if (hit.noteId == noteId) continue;
        if (!perNote.containsKey(hit.noteId)) {
          perNote[hit.noteId] = Backlink(
            noteId: hit.noteId,
            noteTitle: '',
            snippet: hit.snippet,
            updatedAt: 0,
          );
        }
      }
    }

    // 2) Wiki-link substring search on note ID. The FTS index stores plain
    // text only, so use a LIKE on the raw block content.
    final wikiHits = await _db.customSelect(
      'SELECT b.note_id AS note_id, b.id AS block_id '
      'FROM note_blocks b '
      'WHERE b.deleted = 0 AND b.note_id != ? '
      'AND b.content_json LIKE ? '
      'LIMIT ?',
      variables: [
        Variable.withString(noteId),
        Variable.withString('%[[$noteId]]%'),
        Variable.withInt(limit),
      ],
      readsFrom: {_db.noteBlocks},
    ).get();
    for (final row in wikiHits) {
      final nid = row.read<String>('note_id');
      perNote.putIfAbsent(
        nid,
        () => Backlink(
          noteId: nid,
          noteTitle: '',
          snippet: '[[$noteId]]',
          updatedAt: 0,
        ),
      );
    }

    if (perNote.isEmpty) return const [];

    // Resolve titles + updatedAt for each backlink note. Filter to the
    // current user's notes only (and not-deleted).
    final ids = perNote.keys.toList();
    final placeholders = List.filled(ids.length, '?').join(',');
    final noteRows = await _db.customSelect(
      'SELECT id, title, updated_at FROM sync_notes '
      'WHERE user_id = ? AND deleted = 0 AND id IN ($placeholders)',
      variables: [
        Variable.withString(userId),
        ...ids.map(Variable.withString),
      ],
      readsFrom: {_db.syncNotes},
    ).get();

    final results = <Backlink>[];
    for (final row in noteRows) {
      final id = row.read<String>('id');
      final existing = perNote[id]!;
      results.add(Backlink(
        noteId: id,
        noteTitle: row.read<String>('title'),
        snippet: existing.snippet,
        updatedAt: row.read<int>('updated_at'),
      ));
    }

    results.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return results.take(limit).toList();
  }
}
