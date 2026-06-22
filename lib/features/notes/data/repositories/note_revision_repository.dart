import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/database/sync_database.dart';
import '../../../../core/sync/models/note_block_model.dart';
import '../../../../core/sync/models/note_model.dart';
import '../../domain/models/note_revision.dart';

/// Top-level function for compute() — serializes note + blocks snapshot JSON
/// off the main isolate.
String _encodeRevisionSnapshot(
    ({Map<String, dynamic> note, List<Map<String, dynamic>> blocks}) data) =>
    jsonEncode({'note': data.note, 'blocks': data.blocks});

/// Repository for note revision snapshots.
///
/// This is a local-only repository — it does NOT create oplog entries
/// and revisions are never synced to the server.
class NoteRevisionRepository {
  final SyncDatabase _db;

  /// Maximum revisions to keep per note.
  static const int maxRevisionsPerNote = 50;

  /// Minimum interval between revisions for the same note (30 seconds).
  /// Prevents flooding the history with micro-edits from debounced auto-save.
  static const Duration minRevisionInterval = Duration(seconds: 30);

  NoteRevisionRepository(this._db);

  /// Create a snapshot revision of the current note state.
  ///
  /// Skips creation if a revision for this note was created within
  /// [minRevisionInterval], or if the snapshot exceeds 1 MB.
  ///
  /// Set [force] to `true` to bypass the deduplication interval (e.g. when
  /// creating a pre-restore safety snapshot).
  Future<void> createRevision(
    NoteModel note,
    List<NoteBlockModel> blocks, {
    bool force = false,
  }) async {
    // Deduplication: skip if a recent revision exists for this note.
    if (!force) {
      final cutoff = DateTime.now()
          .subtract(minRevisionInterval)
          .millisecondsSinceEpoch;
      final recent = await _db.customSelect(
        'SELECT 1 FROM note_revisions '
        'WHERE note_id = ? AND created_at > ? LIMIT 1',
        variables: [
          Variable.withString(note.id),
          Variable.withInt(cutoff),
        ],
      ).getSingleOrNull();
      if (recent != null) return;
    }

    final snapshot = await compute(
      _encodeRevisionSnapshot,
      (note: note.toJson(), blocks: blocks.map((b) => b.toJson()).toList()),
    );

    // Guard: skip if snapshot exceeds 1 MB.
    if (snapshot.length > 1024 * 1024) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.transaction(() async {
      await _db.into(_db.noteRevisions).insert(
            NoteRevisionsCompanion.insert(
              id: const Uuid().v4(),
              noteId: note.id,
              snapshotJson: snapshot,
              createdAt: now,
            ),
          );
      await _trimRevisions(note.id);
    });
  }

  /// Watch all revisions for a note, newest first.
  Stream<List<NoteRevisionSnapshot>> watchRevisions(String noteId) {
    final query = _db.select(_db.noteRevisions)
      ..where((r) => r.noteId.equals(noteId))
      ..orderBy([(r) => OrderingTerm.desc(r.createdAt)]);

    return query.watch().map(
          (rows) => rows.map(_toSnapshot).toList(),
        );
  }

  /// Get a single revision by ID.
  Future<NoteRevisionSnapshot?> getRevision(String revisionId) async {
    final query = _db.select(_db.noteRevisions)
      ..where((r) => r.id.equals(revisionId));
    final row = await query.getSingleOrNull();
    return row != null ? _toSnapshot(row) : null;
  }

  /// Delete all revisions for a note.
  Future<void> deleteRevisionsForNote(String noteId) async {
    await (_db.delete(_db.noteRevisions)
          ..where((r) => r.noteId.equals(noteId)))
        .go();
  }

  /// Keep only the newest [maxRevisionsPerNote] revisions for a note.
  Future<void> _trimRevisions(String noteId) async {
    // Get IDs of revisions beyond the limit, ordered oldest first.
    final excess = await _db.customSelect(
      'SELECT id FROM note_revisions '
      'WHERE note_id = ? '
      'ORDER BY created_at DESC '
      'LIMIT -1 OFFSET ?',
      variables: [
        Variable.withString(noteId),
        Variable.withInt(maxRevisionsPerNote),
      ],
    ).get();

    if (excess.isEmpty) return;

    final idsToDelete = excess.map((r) => r.read<String>('id')).toList();
    await (_db.delete(_db.noteRevisions)
          ..where((r) => r.id.isIn(idsToDelete)))
        .go();
  }

  NoteRevisionSnapshot _toSnapshot(NoteRevision row) {
    return NoteRevisionSnapshot(
      id: row.id,
      noteId: row.noteId,
      snapshotJson: row.snapshotJson,
      createdAt: DateTime.fromMillisecondsSinceEpoch(row.createdAt),
    );
  }
}
