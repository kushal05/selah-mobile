import 'package:drift/drift.dart';

import '../../../../core/database/sync_database.dart';

/// Virtual query-based collections computed from existing tables.
/// No new DB tables — everything is derived from sync_notes + sync_note_tags.
class SmartCollectionsService {
  final SyncDatabase _db;
  final String _userId;

  SmartCollectionsService(this._db, this._userId);

  // Each collection is a live query. They were one-shot `.get()` calls behind
  // cached FutureProviders, which nothing ever invalidated: tag a note and it
  // stayed under Untagged, write a new one and it never reached Recently
  // Edited, for the rest of the session. `.watch()` re-runs when a table the
  // query reads from is written to — which drift can only know if it is told,
  // hence `readsFrom` on every one. Leave it off and the stream emits once and
  // falls silent, which is the old bug again with a different shape.
  //
  // They answer with note ids and nothing else. Their consumers want only the
  // ids (to pick notes out of the list the screen already has) and the count
  // (for the chip). `SELECT *` carried every note's body across with them on
  // every re-run: 30ms against 1ms at 2,000 notes of 4KB, before the copy out
  // of the background isolate.
  //
  // And they stay quiet when nothing changed. A live query re-runs on any
  // write to its tables, and most writes — an autosave of a note's text — leave
  // a collection exactly as it was: four of every five re-runs in a burst of
  // saves. `distinct` stops those at the source, so they never reach the
  // list's re-sort or the screen.

  /// The 20 most recently edited notes, newest first.
  Stream<List<String>> watchRecentlyEditedIds({int limit = 20}) => _ids(
        'SELECT id FROM sync_notes '
        'WHERE user_id = ? AND deleted = 0 '
        'ORDER BY updated_at DESC LIMIT ?',
        [Variable.withString(_userId), Variable.withInt(limit)],
        {_db.syncNotes},
      );

  /// Notes with no live tag. Reads both tables: tagging a note changes only
  /// sync_note_tags, and that alone has to move the note out of this list.
  Stream<List<String>> watchUntaggedIds() => _ids(
        'SELECT n.id FROM sync_notes n '
        'LEFT JOIN sync_note_tags t ON t.note_id = n.id AND t.deleted = 0 '
        'WHERE n.user_id = ? AND n.deleted = 0 AND t.id IS NULL '
        'ORDER BY n.updated_at DESC',
        [Variable.withString(_userId)],
        {_db.syncNotes, _db.syncNoteTags},
      );

  /// Notes not touched in [days] days.
  ///
  /// The cutoff is fixed when the stream starts, so a note that crosses the
  /// line while the collection is open joins it on the next write or the next
  /// time the collection is opened, not on the hour. Edits — the case that
  /// matters, since editing a note takes it *out* of here — apply at once.
  Stream<List<String>> watchStaleIds({int days = 30}) {
    final cutoff =
        DateTime.now().subtract(Duration(days: days)).millisecondsSinceEpoch;
    return _ids(
      'SELECT id FROM sync_notes '
      'WHERE user_id = ? AND deleted = 0 AND updated_at < ? '
      'ORDER BY updated_at ASC',
      [Variable.withString(_userId), Variable.withInt(cutoff)],
      {_db.syncNotes},
    );
  }

  Stream<List<String>> _ids(
    String sql,
    List<Variable> variables,
    Set<TableInfo> readsFrom,
  ) =>
      _db
          .customSelect(sql, variables: variables, readsFrom: readsFrom)
          .watch()
          .map((rows) => [for (final r in rows) r.read<String>('id')])
          .distinct(_sameIds);

  static bool _sameIds(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
