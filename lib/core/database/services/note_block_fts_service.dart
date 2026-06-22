import 'dart:convert';

import 'package:drift/drift.dart';

import '../sync_database.dart';
import 'note_fts_query_builder.dart';

/// Service for maintaining the `note_blocks_fts` FTS5 virtual table.
///
/// The FTS table is a regular (non-contentless) FTS5 table that stores its
/// own copy of the indexed text. This enables `highlight()` for search
/// snippets and simplifies deletes (no need to supply original text).
///
/// All mutation methods must be called INSIDE an existing transaction.
/// This service does NOT manage its own transactions.
class NoteBlockFtsService {
  final SyncDatabase _db;

  NoteBlockFtsService(this._db);

  /// Insert a block into the FTS index.
  ///
  /// Must be called within an existing transaction.
  Future<void> insertIntoFts({
    required String blockId,
    required String noteId,
    required String contentJson,
  }) async {
    final plainText = extractPlainText(contentJson);
    if (plainText.isEmpty) return;

    await _db.customStatement(
      'INSERT INTO note_blocks_fts(plain_text, note_id, block_id) '
      'VALUES (?, ?, ?)',
      [plainText, noteId, blockId],
    );
  }

  /// Remove a block from the FTS index.
  ///
  /// Must be called within an existing transaction.
  Future<void> removeFromFts({
    required String blockId,
  }) async {
    await _db.customStatement(
      'DELETE FROM note_blocks_fts WHERE block_id = ?',
      [blockId],
    );
  }

  /// Update FTS for a block whose content changed.
  ///
  /// Removes old entry and inserts new one.
  /// Must be called within an existing transaction.
  Future<void> updateFts({
    required String blockId,
    required String noteId,
    required String newContentJson,
  }) async {
    await removeFromFts(blockId: blockId);
    await insertIntoFts(
      blockId: blockId,
      noteId: noteId,
      contentJson: newContentJson,
    );
  }

  /// Search the FTS index and return matching results with snippets.
  ///
  /// Uses [NoteFtsQueryBuilder] for safe FTS5 MATCH expressions.
  Future<List<NoteBlockFtsResult>> search(
    String query, {
    int limit = 100,
    String hlOpen = '\u00AB',
    String hlClose = '\u00BB',
  }) async {
    final ftsQuery = NoteFtsQueryBuilder.build(query);
    if (ftsQuery == null) return [];

    try {
      final rows = await _db.customSelect(
        'SELECT block_id, note_id, '
        'highlight(note_blocks_fts, 0, ?, ?) AS snippet '
        'FROM note_blocks_fts '
        'WHERE plain_text MATCH ? '
        'ORDER BY rank '
        'LIMIT ?',
        variables: [
          Variable.withString(hlOpen),
          Variable.withString(hlClose),
          Variable.withString(ftsQuery),
          Variable.withInt(limit),
        ],
      ).get();

      return rows
          .map((r) => NoteBlockFtsResult(
                blockId: r.read<String>('block_id'),
                noteId: r.read<String>('note_id'),
                snippet: r.read<String>('snippet'),
              ))
          .toList();
    } catch (_) {
      // FTS query error (malformed MATCH, etc.) — return empty
      return [];
    }
  }

  /// Search blocks within a specific note, returning matching block IDs.
  ///
  /// Uses the UNINDEXED `note_id` column to filter after the MATCH.
  Future<List<String>> searchBlockIdsInNote(
    String noteId,
    String query, {
    int limit = 500,
  }) async {
    final ftsQuery = NoteFtsQueryBuilder.build(query);
    if (ftsQuery == null) return [];

    try {
      final rows = await _db.customSelect(
        'SELECT block_id '
        'FROM note_blocks_fts '
        'WHERE plain_text MATCH ? AND note_id = ? '
        'LIMIT ?',
        variables: [
          Variable.withString(ftsQuery),
          Variable.withString(noteId),
          Variable.withInt(limit),
        ],
      ).get();

      return rows.map((r) => r.read<String>('block_id')).toList();
    } catch (_) {
      return [];
    }
  }

  /// Extract readable plain text from a note block's contentJson string.
  ///
  /// Mirrors [NoteBlockModel.plainText] getter. Handles two formats:
  /// - `{"text": "some text"}` → `"some text"`
  /// - `{"spans": [{"text": "foo"}, {"text": "bar"}]}` → `"foobar"`
  static String extractPlainText(String contentJsonStr) {
    try {
      final map = jsonDecode(contentJsonStr) as Map<String, dynamic>;
      if (map.containsKey('text')) {
        return (map['text'] as String?) ?? '';
      }
      if (map.containsKey('spans')) {
        final spans = map['spans'] as List?;
        if (spans != null) {
          return spans
              .map((s) => (s as Map<String, dynamic>)['text'] ?? '')
              .join();
        }
      }
    } catch (_) {}
    return '';
  }
}

/// A single FTS search result for a note block.
class NoteBlockFtsResult {
  final String blockId;
  final String noteId;
  final String snippet;

  const NoteBlockFtsResult({
    required this.blockId,
    required this.noteId,
    required this.snippet,
  });
}
