import 'package:drift/drift.dart';

import '../../../../core/database/sync_database.dart';
import '../../../../core/sync/models/note_model.dart';

/// Virtual query-based collections computed from existing tables.
/// No new DB tables — everything is derived from sync_notes + sync_note_tags.
class SmartCollectionsService {
  final SyncDatabase _db;
  final String _userId;

  SmartCollectionsService(this._db, this._userId);

  /// Recently edited notes (updatedAt DESC, limit 20).
  Future<List<NoteModel>> getRecentlyEdited({int limit = 20}) async {
    final rows = await _db.customSelect(
      'SELECT * FROM sync_notes '
      'WHERE user_id = ? AND deleted = 0 '
      'ORDER BY updated_at DESC LIMIT ?',
      variables: [
        Variable.withString(_userId),
        Variable.withInt(limit),
      ],
    ).get();
    return rows.map(_toModel).toList();
  }

  /// Notes that have no tags (LEFT JOIN sync_note_tags IS NULL).
  Future<List<NoteModel>> getUntaggedNotes() async {
    final rows = await _db.customSelect(
      'SELECT n.* FROM sync_notes n '
      'LEFT JOIN sync_note_tags t ON t.note_id = n.id AND t.deleted = 0 '
      'WHERE n.user_id = ? AND n.deleted = 0 AND t.id IS NULL '
      'ORDER BY n.updated_at DESC',
      variables: [Variable.withString(_userId)],
    ).get();
    return rows.map(_toModel).toList();
  }

  /// Notes not updated in the last [days] days.
  Future<List<NoteModel>> getStaleNotes({int days = 30}) async {
    final cutoff = DateTime.now()
        .subtract(Duration(days: days))
        .millisecondsSinceEpoch;

    final rows = await _db.customSelect(
      'SELECT * FROM sync_notes '
      'WHERE user_id = ? AND deleted = 0 AND updated_at < ? '
      'ORDER BY updated_at ASC',
      variables: [
        Variable.withString(_userId),
        Variable.withInt(cutoff),
      ],
    ).get();
    return rows.map(_toModel).toList();
  }

  NoteModel _toModel(QueryRow row) {
    return NoteModel(
      id: row.read<String>('id'),
      folderId: row.read<String>('folder_id'),
      userId: row.read<String>('user_id'),
      title: row.read<String>('title'),
      updatedAt: row.read<int>('updated_at'),
      version: row.read<int>('version'),
      deleted: row.read<int>('deleted'),
      createdAt: row.read<int>('created_at'),
      preacherId: row.readNullable<String>('preacher_id'),
      noteDate: row.readNullable<int>('note_date'),
    );
  }
}
