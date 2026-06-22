import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/sync_database.dart';

/// Domain model for a Bible chapter bookmark.
class BibleBookmarkEntry {
  final String id;
  final String userId;
  final int bookId;
  final String bookName;
  final int chapter;
  final String translation;
  final int createdAt;

  const BibleBookmarkEntry({
    required this.id,
    required this.userId,
    required this.bookId,
    required this.bookName,
    required this.chapter,
    required this.translation,
    required this.createdAt,
  });

  factory BibleBookmarkEntry.fromRow(Map<String, dynamic> row) {
    return BibleBookmarkEntry(
      id: row['id'] as String,
      userId: row['user_id'] as String,
      bookId: row['book_id'] as int,
      bookName: row['book_name'] as String,
      chapter: row['chapter'] as int,
      translation: row['translation'] as String,
      createdAt: row['created_at'] as int,
    );
  }
}

/// Local-only repository for Bible chapter bookmarks.
///
/// Uses raw SQL rather than Drift DSL accessors to keep the implementation
/// simple and independent of generated code changes.
class BibleBookmarkRepository {
  final SyncDatabase _db;
  final String _userId;

  BibleBookmarkRepository(this._db, this._userId);

  static const _table = 'bible_bookmarks';

  /// Watch all bookmarks for the current user, newest first.
  Stream<List<BibleBookmarkEntry>> watchBookmarks() {
    return _db
        .customSelect(
          'SELECT * FROM $_table WHERE user_id = ? ORDER BY created_at DESC',
          variables: [Variable.withString(_userId)],
          readsFrom: {_db.bibleBookmarks},
        )
        .watch()
        .map((rows) =>
            rows.map((r) => BibleBookmarkEntry.fromRow(r.data)).toList());
  }

  /// Whether a specific (bookId, chapter) is bookmarked by the current user.
  Stream<bool> watchIsBookmarked({
    required int bookId,
    required int chapter,
  }) {
    return _db
        .customSelect(
          'SELECT id FROM $_table WHERE user_id = ? AND book_id = ? AND chapter = ? LIMIT 1',
          variables: [
            Variable.withString(_userId),
            Variable.withInt(bookId),
            Variable.withInt(chapter),
          ],
          readsFrom: {_db.bibleBookmarks},
        )
        .watch()
        .map((rows) => rows.isNotEmpty);
  }

  /// Toggle bookmark for a chapter. Returns true if now bookmarked, false if removed.
  Future<bool> toggleBookmark({
    required int bookId,
    required String bookName,
    required int chapter,
    required String translation,
  }) async {
    final existing = await _db.customSelect(
      'SELECT id FROM $_table WHERE user_id = ? AND book_id = ? AND chapter = ? LIMIT 1',
      variables: [
        Variable.withString(_userId),
        Variable.withInt(bookId),
        Variable.withInt(chapter),
      ],
    ).getSingleOrNull();

    if (existing != null) {
      await _db.customStatement(
        'DELETE FROM $_table WHERE id = ?',
        [existing.data['id'] as String],
      );
      return false;
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.customStatement(
      'INSERT OR IGNORE INTO $_table (id, user_id, book_id, book_name, chapter, translation, created_at) '
      'VALUES (?, ?, ?, ?, ?, ?, ?)',
      [
        const Uuid().v4(),
        _userId,
        bookId,
        bookName,
        chapter,
        translation,
        now,
      ],
    );
    return true;
  }

  /// Delete a bookmark by id.
  Future<void> deleteBookmark(String id) async {
    await _db.customStatement(
      'DELETE FROM $_table WHERE id = ?',
      [id],
    );
  }
}
