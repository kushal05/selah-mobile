import 'dart:async';

import 'package:drift/drift.dart';

import '../../database/sync_database.dart';
import '../models/oplog_entry.dart';
import '../models/bible_reference_history_model.dart';
import 'base_sync_repository.dart';
import '../../testing/test_clock.dart';

/// Repository for Bible reference history operations
///
/// Per spec: Every write is transactional with oplog entry.
/// Supports smart deduplication — if the same reference was opened within
/// the last 5 minutes, updates the timestamp instead of inserting a new entry.
class BibleReferenceHistoryRepository
    extends BaseSyncRepository<BibleReferenceHistoryModel> {
  final SyncDatabase _db;
  final String _deviceId;

  /// Maximum number of history entries per user before pruning oldest.
  static const int maxHistoryEntries = 1000;

  /// Deduplication window in milliseconds (5 minutes).
  static const int dedupWindowMs = 5 * 60 * 1000;

  BibleReferenceHistoryRepository(this._db, this._deviceId);

  @override
  String get deviceId => _deviceId;

  @override
  OplogEntityType get entityType => OplogEntityType.bibleReferenceHistory;

  // ==================== READ OPERATIONS ====================

  /// Watch recent history for a user (reactive stream), limited to [limit] entries.
  Stream<List<BibleReferenceHistoryModel>> watchRecentHistory(
      String userId, {int limit = 50}) {
    final query = _db.select(_db.bibleReferenceHistory)
      ..where((h) => h.userId.equals(userId) & h.deleted.equals(0))
      ..orderBy([(h) => OrderingTerm.desc(h.openedAt)])
      ..limit(limit);

    return query.watch().map((rows) => rows.map(_toModel).toList());
  }

  /// Get all non-deleted history for a user, ordered by openedAt descending.
  Future<List<BibleReferenceHistoryModel>> getAllHistory(String userId) async {
    final query = _db.select(_db.bibleReferenceHistory)
      ..where((h) => h.userId.equals(userId) & h.deleted.equals(0))
      ..orderBy([(h) => OrderingTerm.desc(h.openedAt)]);

    final rows = await query.get();
    return rows.map(_toModel).toList();
  }

  /// Get a single history entry by ID.
  Future<BibleReferenceHistoryModel?> getById(String id) async {
    final query = _db.select(_db.bibleReferenceHistory)
      ..where((h) => h.id.equals(id));

    final row = await query.getSingleOrNull();
    return row != null ? _toModel(row) : null;
  }

  /// Find a recent duplicate entry (same book, chapter, verseStart, translation)
  /// opened within the dedup window.
  Future<BibleReferenceHistoryModel?> _findRecentDuplicate({
    required String userId,
    required String book,
    required int chapter,
    int? verseStart,
    required String translation,
  }) async {
    final cutoff = TestClock.now() - dedupWindowMs;

    final query = _db.select(_db.bibleReferenceHistory)
      ..where((h) =>
          h.userId.equals(userId) &
          h.deleted.equals(0) &
          h.book.equals(book) &
          h.chapter.equals(chapter) &
          h.translation.equals(translation) &
          h.openedAt.isBiggerThanValue(cutoff));

    if (verseStart != null) {
      query.where((h) => h.verseStart.equals(verseStart));
    } else {
      query.where((h) => h.verseStart.isNull());
    }

    query.orderBy([(h) => OrderingTerm.desc(h.openedAt)]);
    query.limit(1);

    final row = await query.getSingleOrNull();
    return row != null ? _toModel(row) : null;
  }

  // ==================== WRITE OPERATIONS ====================

  /// Log a Bible reference being opened.
  ///
  /// Smart deduplication: if the same reference was opened within the last
  /// 5 minutes, updates the existing entry's openedAt instead of inserting.
  /// After logging, prunes entries beyond [maxHistoryEntries].
  Future<BibleReferenceHistoryModel> logReference({
    required String userId,
    required String book,
    required int chapter,
    int? verseStart,
    int? verseEnd,
    required String translation,
  }) async {
    // Check for recent duplicate
    final existing = await _findRecentDuplicate(
      userId: userId,
      book: book,
      chapter: chapter,
      verseStart: verseStart,
      translation: translation,
    );

    if (existing != null) {
      // Update existing entry's timestamp
      return _updateTimestamp(existing);
    }

    // Create new entry
    final entry = BibleReferenceHistoryModel.create(
      id: generateId(),
      userId: userId,
      book: book,
      chapter: chapter,
      verseStart: verseStart,
      verseEnd: verseEnd,
      translation: translation,
    );

    final oplogEntry = createInsertOp(entry);

    await _db.transaction(() async {
      await _db.into(_db.bibleReferenceHistory).insert(_toCompanion(entry));
      await _db.into(_db.oplog).insert(_oplogToCompanion(oplogEntry));
    });

    // Prune old entries (best-effort, errors caught internally)
    unawaited(_pruneOldEntries(userId));

    return entry;
  }

  /// Update an existing entry's openedAt timestamp (for dedup).
  Future<BibleReferenceHistoryModel> _updateTimestamp(
      BibleReferenceHistoryModel existing) async {
    final updated = existing.copyWithUpdate();
    final oplogEntry = createUpdateOp(updated);

    await _db.transaction(() async {
      await (_db.update(_db.bibleReferenceHistory)
            ..where((h) => h.id.equals(existing.id)))
          .write(_toCompanion(updated));
      await _db.into(_db.oplog).insert(_oplogToCompanion(oplogEntry));
    });

    return updated;
  }

  /// Soft delete a history entry.
  Future<void> deleteEntry(String id) async {
    final existing = await getById(id);
    if (existing == null) return;

    final deletedEntry = existing.softDelete();
    final oplogEntry = createDeleteOp(deletedEntry);

    await _db.transaction(() async {
      await (_db.update(_db.bibleReferenceHistory)
            ..where((h) => h.id.equals(id)))
          .write(_toCompanion(deletedEntry));
      await _db.into(_db.oplog).insert(_oplogToCompanion(oplogEntry));
    });
  }

  /// Soft delete all history entries for a user.
  /// Processes in batches of 100 to limit memory and transaction size.
  Future<void> clearHistory(String userId) async {
    const batchSize = 100;
    while (true) {
      final query = _db.select(_db.bibleReferenceHistory)
        ..where((h) => h.userId.equals(userId) & h.deleted.equals(0))
        ..limit(batchSize);
      final rows = await query.get();
      if (rows.isEmpty) break;

      final entries = rows.map(_toModel).toList();
      await _db.transaction(() async {
        for (final entry in entries) {
          final deletedEntry = entry.softDelete();
          final oplogEntry = createDeleteOp(deletedEntry);

          await (_db.update(_db.bibleReferenceHistory)
                ..where((h) => h.id.equals(entry.id)))
              .write(_toCompanion(deletedEntry));
          await _db.into(_db.oplog).insert(_oplogToCompanion(oplogEntry));
        }
      });
    }
  }

  /// Prune history entries beyond [maxHistoryEntries] (best-effort).
  Future<void> _pruneOldEntries(String userId) async {
    try {
      final count = await _db.customSelect(
        'SELECT COUNT(*) as count FROM bible_reference_history '
        'WHERE user_id = ? AND deleted = 0',
        variables: [Variable.withString(userId)],
      ).getSingle();

      final total = count.read<int>('count');
      if (total <= maxHistoryEntries) return;

      // Find entries to prune (oldest beyond limit)
      final toPrune = await _db.customSelect(
        'SELECT id FROM bible_reference_history '
        'WHERE user_id = ? AND deleted = 0 '
        'ORDER BY opened_at DESC '
        'LIMIT -1 OFFSET ?',
        variables: [
          Variable.withString(userId),
          Variable.withInt(maxHistoryEntries),
        ],
      ).get();

      if (toPrune.isEmpty) return;

      await _db.transaction(() async {
        for (final row in toPrune) {
          final entryId = row.read<String>('id');
          final existing = await getById(entryId);
          if (existing == null) continue;

          final deletedEntry = existing.softDelete();
          final oplogEntry = createDeleteOp(deletedEntry);

          await (_db.update(_db.bibleReferenceHistory)
                ..where((h) => h.id.equals(entryId)))
              .write(_toCompanion(deletedEntry));
          await _db.into(_db.oplog).insert(_oplogToCompanion(oplogEntry));
        }
      });
    } catch (_) {
      // Best-effort pruning — don't block the main operation
    }
  }

  // ==================== HELPER METHODS ====================

  /// Convert database row to domain model
  BibleReferenceHistoryModel _toModel(BibleReferenceHistoryData row) {
    return BibleReferenceHistoryModel(
      id: row.id,
      userId: row.userId,
      book: row.book,
      chapter: row.chapter,
      verseStart: row.verseStart,
      verseEnd: row.verseEnd,
      translation: row.translation,
      openedAt: row.openedAt,
      updatedAt: row.updatedAt,
      version: row.version,
      deleted: row.deleted,
      createdAt: row.createdAt,
    );
  }

  /// Convert domain model to database companion
  BibleReferenceHistoryCompanion _toCompanion(
      BibleReferenceHistoryModel model) {
    return BibleReferenceHistoryCompanion(
      id: Value(model.id),
      userId: Value(model.userId),
      book: Value(model.book),
      chapter: Value(model.chapter),
      verseStart: Value(model.verseStart),
      verseEnd: Value(model.verseEnd),
      translation: Value(model.translation),
      openedAt: Value(model.openedAt),
      updatedAt: Value(model.updatedAt),
      version: Value(model.version),
      deleted: Value(model.deleted),
      createdAt: Value(model.createdAt),
    );
  }

  /// Convert oplog entry to database companion
  OplogCompanion _oplogToCompanion(OplogEntry entry) {
    return OplogCompanion(
      opId: Value(entry.opId),
      entityType: Value(entry.entityType.toDbValue()),
      entityId: Value(entry.entityId),
      operation: Value(entry.operation.toDbValue()),
      payloadJson: Value(entry.payloadJson),
      timestamp: Value(entry.timestamp),
      deviceId: Value(entry.deviceId),
      synced: Value(entry.synced ? 1 : 0),
      entityVersion: Value(entry.entityVersion),
      serverTimestamp: Value(entry.serverTimestamp),
    );
  }
}
