import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/sync_database.dart';
import '../../../core/sync/models/oplog_entry.dart';
import '../../../core/sync/repositories/base_sync_repository.dart';
import '../domain/models/bible_verse_note_entity.dart';

/// Repository for notes written on a Bible verse.
///
/// Extends [BaseSyncRepository] so every write is one transaction of the row
/// plus its oplog entry. Flutter-only entity type (bibleVerseNote) pending
/// Worker support, like highlights.
class BibleVerseNoteRepository
    extends BaseSyncRepository<BibleVerseNoteEntity> {
  final SyncDatabase _db;
  final String _deviceId;
  final String _userId;

  BibleVerseNoteRepository(this._db, this._deviceId, this._userId);

  @override
  String get deviceId => _deviceId;

  @override
  OplogEntityType get entityType => OplogEntityType.bibleVerseNote;

  /// Watch the notes whose range covers [verse], newest first.
  Stream<List<BibleVerseNoteEntity>> watchNotesForVerse({
    required int bookId,
    required int chapter,
    required int verse,
  }) {
    final query = _db.select(_db.bibleVerseNotes)
      ..where(
        (n) =>
            n.bookId.equals(bookId) &
            n.chapter.equals(chapter) &
            n.verseStart.isSmallerOrEqualValue(verse) &
            n.verseEnd.isBiggerOrEqualValue(verse) &
            n.deleted.equals(0),
      )
      ..orderBy([(n) => OrderingTerm.desc(n.createdAt)]);
    return query.watch().map((rows) => rows.map(_toEntity).toList());
  }

  /// Watch every note in a chapter, newest first.
  Stream<List<BibleVerseNoteEntity>> watchNotesForChapter({
    required int bookId,
    required int chapter,
  }) {
    final query = _db.select(_db.bibleVerseNotes)
      ..where(
        (n) =>
            n.bookId.equals(bookId) &
            n.chapter.equals(chapter) &
            n.deleted.equals(0),
      )
      ..orderBy([(n) => OrderingTerm.desc(n.createdAt)]);
    return query.watch().map((rows) => rows.map(_toEntity).toList());
  }

  /// Save a note on [verse] (through [verseEnd] for a run of verses) and
  /// record an INSERT oplog entry.
  Future<BibleVerseNoteEntity> addNote({
    required int bookId,
    required int chapter,
    required int verse,
    int? verseEnd,
    required String content,
  }) async {
    final end = verseEnd ?? verse;
    final now = DateTime.now().millisecondsSinceEpoch;
    final entity = BibleVerseNoteEntity(
      id: const Uuid().v4(),
      userId: _userId,
      bookId: bookId,
      chapter: chapter,
      verseStart: verse <= end ? verse : end,
      verseEnd: verse <= end ? end : verse,
      content: content,
      version: 1,
      createdAt: now,
      updatedAt: now,
    );
    final oplogEntry = createInsertOp(entity);

    await _db.transaction(() async {
      await _db.into(_db.bibleVerseNotes).insert(_toCompanion(entity));
      await _db.into(_db.oplog).insert(_oplogToCompanion(oplogEntry));
    });
    return entity;
  }

  /// The verse numbers in a chapter that have at least one note, to mark them
  /// in the chapter list. A note over a range marks every verse in it.
  Stream<Set<int>> watchNotedVerses({
    required int bookId,
    required int chapter,
  }) {
    final query = _db.select(_db.bibleVerseNotes)
      ..where(
        (n) =>
            n.bookId.equals(bookId) &
            n.chapter.equals(chapter) &
            n.deleted.equals(0),
      );
    return query.watch().map((rows) => {
          for (final r in rows)
            for (var v = r.verseStart; v <= r.verseEnd; v++) v,
        });
  }

  /// Change a note's text and record an UPDATE oplog entry.
  Future<void> updateNote(BibleVerseNoteEntity note, String content) async {
    final updated = note.copyWithUpdate(content: content);
    final oplogEntry = createUpdateOp(updated);

    await _db.transaction(() async {
      await (_db.update(_db.bibleVerseNotes)
            ..where((n) => n.id.equals(note.id)))
          .write(BibleVerseNotesCompanion(
        content: Value(updated.content),
        version: Value(updated.version),
        updatedAt: Value(updated.updatedAt),
      ));
      await _db.into(_db.oplog).insert(_oplogToCompanion(oplogEntry));
    });
  }

  /// Soft-delete a note and record a DELETE oplog entry.
  Future<void> deleteNote(BibleVerseNoteEntity note) async {
    final deleted = note.asDeleted();
    final oplogEntry = createDeleteOp(deleted);

    await _db.transaction(() async {
      await (_db.update(_db.bibleVerseNotes)
            ..where((n) => n.id.equals(note.id)))
          .write(BibleVerseNotesCompanion(
        deleted: const Value(1),
        version: Value(deleted.version),
        updatedAt: Value(deleted.updatedAt),
      ));
      await _db.into(_db.oplog).insert(_oplogToCompanion(oplogEntry));
    });
  }

  BibleVerseNoteEntity _toEntity(BibleVerseNote row) {
    return BibleVerseNoteEntity(
      id: row.id,
      userId: row.userId,
      bookId: row.bookId,
      chapter: row.chapter,
      verseStart: row.verseStart,
      verseEnd: row.verseEnd,
      content: row.content,
      version: row.version,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
    );
  }

  BibleVerseNotesCompanion _toCompanion(BibleVerseNoteEntity e) {
    return BibleVerseNotesCompanion(
      id: Value(e.id),
      userId: Value(e.userId),
      bookId: Value(e.bookId),
      chapter: Value(e.chapter),
      verseStart: Value(e.verseStart),
      verseEnd: Value(e.verseEnd),
      content: Value(e.content),
      version: Value(e.version),
      deleted: const Value(0),
      createdAt: Value(e.createdAt),
      updatedAt: Value(e.updatedAt),
    );
  }

  OplogCompanion _oplogToCompanion(OplogEntry entry) {
    return OplogCompanion.insert(
      opId: entry.opId,
      entityType: entry.entityType.toDbValue(),
      entityId: entry.entityId,
      operation: entry.operation.toDbValue(),
      payloadJson: entry.payloadJson,
      timestamp: entry.timestamp,
      deviceId: entry.deviceId,
      entityVersion: entry.entityVersion,
    );
  }
}
