import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/sync_database.dart';
import '../../../core/sync/models/oplog_entry.dart';
import '../../../core/sync/repositories/base_sync_repository.dart';
import '../domain/models/bible_highlight_entity.dart';

/// Repository for Bible verse highlights.
///
/// Extends [BaseSyncRepository] so every write creates an oplog entry,
/// enabling highlights to sync across the user's devices.
/// Flutter-only entity type (bibleHighlight) pending Worker support.
class BibleHighlightRepository
    extends BaseSyncRepository<BibleHighlightEntity> {
  final SyncDatabase _db;
  final String _deviceId;
  final String _userId;

  BibleHighlightRepository(this._db, this._deviceId, this._userId);

  @override
  String get deviceId => _deviceId;

  @override
  OplogEntityType get entityType => OplogEntityType.bibleHighlight;

  // ── READ ──────────────────────────────────────────────────────────────────

  /// Watch all non-deleted highlights for a specific chapter (reactive stream).
  Stream<List<BibleHighlightEntity>> watchHighlightsForChapter({
    required int bookId,
    required int chapter,
  }) {
    final query = _db.select(_db.bibleHighlights)
      ..where(
        (h) =>
            h.bookId.equals(bookId) &
            h.chapter.equals(chapter) &
            h.deleted.equals(0),
      );
    return query.watch().map((rows) => rows.map(_toEntity).toList());
  }

  /// Get all non-deleted highlights for a chapter (one-shot).
  Future<List<BibleHighlightEntity>> getHighlightsForChapter({
    required int bookId,
    required int chapter,
  }) async {
    final query = _db.select(_db.bibleHighlights)
      ..where(
        (h) =>
            h.bookId.equals(bookId) &
            h.chapter.equals(chapter) &
            h.deleted.equals(0),
      );
    final rows = await query.get();
    return rows.map(_toEntity).toList();
  }

  /// Watch all non-deleted highlights (for an "all highlights" view).
  Stream<List<BibleHighlightEntity>> watchAllHighlights() {
    final query = _db.select(_db.bibleHighlights)
      ..where((h) => h.deleted.equals(0))
      ..orderBy([(h) => OrderingTerm.desc(h.updatedAt)]);
    return query.watch().map((rows) => rows.map(_toEntity).toList());
  }

  // ── WRITE ─────────────────────────────────────────────────────────────────

  /// Create a new highlight and record an INSERT oplog entry.
  Future<BibleHighlightEntity> createHighlight({
    required int bookId,
    required int chapter,
    required int verseStart,
    required int verseEnd,
    required HighlightColor color,
    String note = '',
  }) async {
    final start = verseStart <= verseEnd ? verseStart : verseEnd;
    final end = verseStart <= verseEnd ? verseEnd : verseStart;
    final now = DateTime.now().millisecondsSinceEpoch;

    final entity = BibleHighlightEntity(
      id: const Uuid().v4(),
      userId: _userId,
      bookId: bookId,
      chapter: chapter,
      verseStart: start,
      verseEnd: end,
      color: color,
      note: note,
      version: 1,
      createdAt: now,
      updatedAt: now,
    );

    final oplogEntry = createInsertOp(entity);

    await _db.transaction(() async {
      await _db.into(_db.bibleHighlights).insert(_toCompanion(entity));
      await _db.into(_db.oplog).insert(_oplogToCompanion(oplogEntry));
    });

    return entity;
  }

  /// Update an existing highlight and record an UPDATE oplog entry.
  ///
  /// Callers must pass an already-bumped entity (via [BibleHighlightEntity.copyWithUpdate]).
  Future<void> updateHighlight(BibleHighlightEntity highlight) async {
    final oplogEntry = createUpdateOp(highlight);

    await _db.transaction(() async {
      await (_db.update(_db.bibleHighlights)
            ..where((h) => h.id.equals(highlight.id)))
          .write(_toCompanion(highlight));
      await _db.into(_db.oplog).insert(_oplogToCompanion(oplogEntry));
    });
  }

  /// Soft-delete a highlight and record a DELETE oplog entry.
  Future<void> deleteHighlight(String id) async {
    final query = _db.select(_db.bibleHighlights)
      ..where((h) => h.id.equals(id));
    final row = await query.getSingleOrNull();
    if (row == null) return;

    final entity = _toEntity(row);
    final deleted = entity.copyWith(
      version: entity.version + 1,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    final oplogEntry = createDeleteOp(deleted);

    await _db.transaction(() async {
      await (_db.update(_db.bibleHighlights)
            ..where((h) => h.id.equals(id)))
          .write(BibleHighlightsCompanion(
            deleted: const Value(1),
            version: Value(deleted.version),
            updatedAt: Value(deleted.updatedAt),
          ));
      await _db.into(_db.oplog).insert(_oplogToCompanion(oplogEntry));
    });
  }

  // ── MAPPERS ───────────────────────────────────────────────────────────────

  BibleHighlightEntity _toEntity(BibleHighlight row) {
    return BibleHighlightEntity(
      id: row.id,
      userId: row.userId,
      bookId: row.bookId,
      chapter: row.chapter,
      verseStart: row.verseStart,
      verseEnd: row.verseEnd,
      color: HighlightColor.fromName(row.color),
      note: row.note,
      version: row.version,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
    );
  }

  BibleHighlightsCompanion _toCompanion(BibleHighlightEntity e) {
    return BibleHighlightsCompanion(
      id: Value(e.id),
      userId: Value(e.userId),
      bookId: Value(e.bookId),
      chapter: Value(e.chapter),
      verseStart: Value(e.verseStart),
      verseEnd: Value(e.verseEnd),
      color: Value(e.color.name),
      note: Value(e.note),
      version: Value(e.version),
      deleted: Value(e.isDeleted ? 1 : 0),
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
