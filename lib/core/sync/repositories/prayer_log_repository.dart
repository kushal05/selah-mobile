import 'package:drift/drift.dart';

import '../../database/sync_database.dart';
import '../models/oplog_entry.dart';
import '../models/prayer_log_model.dart';
import 'base_sync_repository.dart';

/// Repository for prayer log operations
///
/// Per spec: Every write is transactional with oplog entry
class PrayerLogRepository extends BaseSyncRepository<PrayerLogModel> {
  final SyncDatabase _db;
  final String _deviceId;

  PrayerLogRepository(this._db, this._deviceId);

  @override
  String get deviceId => _deviceId;

  @override
  OplogEntityType get entityType => OplogEntityType.prayerLog;

  // ==================== READ OPERATIONS ====================

  /// Get all prayer logs for a user
  Future<List<PrayerLogModel>> getAllLogs(String userId) async {
    final query = _db.select(_db.prayerLogs)
      ..where((l) => l.deleted.equals(0) & l.trashedAt.isNull() & l.userId.equals(userId))
      ..orderBy([(l) => OrderingTerm.desc(l.loggedAt)]);

    final rows = await query.get();
    return rows.map(_toModel).toList();
  }

  /// Get prayer logs for a specific prayer
  Future<List<PrayerLogModel>> getLogsByPrayer(String prayerId, String userId) async {
    final query = _db.select(_db.prayerLogs)
      ..where((l) =>
          l.deleted.equals(0) & l.trashedAt.isNull() & l.userId.equals(userId) & l.prayerId.equals(prayerId))
      ..orderBy([(l) => OrderingTerm.desc(l.loggedAt)]);

    final rows = await query.get();
    return rows.map(_toModel).toList();
  }

  /// Get prayer logs for a specific session date
  Future<List<PrayerLogModel>> getLogsBySessionDate(String sessionDate, String userId) async {
    final query = _db.select(_db.prayerLogs)
      ..where((l) =>
          l.deleted.equals(0) &
          l.trashedAt.isNull() &
          l.userId.equals(userId) &
          l.sessionDate.equals(sessionDate))
      ..orderBy([(l) => OrderingTerm.desc(l.loggedAt)]);

    final rows = await query.get();
    return rows.map(_toModel).toList();
  }

  /// Get a prayer log by ID
  Future<PrayerLogModel?> getLogById(String id) async {
    final query = _db.select(_db.prayerLogs)..where((l) => l.id.equals(id));

    final row = await query.getSingleOrNull();
    return row != null ? _toModel(row) : null;
  }

  /// Check if a prayer has been logged for a given session date
  Future<bool> isPrayerLoggedForDate(String prayerId, String sessionDate, String userId) async {
    final result = await _db.customSelect(
      'SELECT COUNT(*) as count FROM prayer_logs WHERE prayer_id = ? AND session_date = ? AND user_id = ? AND deleted = 0 AND trashed_at IS NULL',
      variables: [
        Variable.withString(prayerId),
        Variable.withString(sessionDate),
        Variable.withString(userId),
      ],
    ).getSingle();
    return result.read<int>('count') > 0;
  }

  /// Get count of logs for a session date
  Future<int> getLogCountForDate(String sessionDate, String userId) async {
    final result = await _db.customSelect(
      'SELECT COUNT(*) as count FROM prayer_logs WHERE session_date = ? AND user_id = ? AND deleted = 0 AND trashed_at IS NULL',
      variables: [
        Variable.withString(sessionDate),
        Variable.withString(userId),
      ],
    ).getSingle();
    return result.read<int>('count');
  }

  /// Get prayer logs for a date range (inclusive).
  /// [startDate] and [endDate] are in 'YYYY-MM-DD' format.
  Future<List<PrayerLogModel>> getLogsByDateRange(
      String startDate, String endDate, String userId) async {
    final query = _db.select(_db.prayerLogs)
      ..where((l) =>
          l.deleted.equals(0) &
          l.trashedAt.isNull() &
          l.userId.equals(userId) &
          l.sessionDate.isBiggerOrEqualValue(startDate) &
          l.sessionDate.isSmallerOrEqualValue(endDate))
      ..orderBy([
        (l) => OrderingTerm.desc(l.sessionDate),
        (l) => OrderingTerm.desc(l.loggedAt),
      ]);

    final rows = await query.get();
    return rows.map(_toModel).toList();
  }

  /// Watch prayer logs for a specific session date (reactive stream)
  Stream<List<PrayerLogModel>> watchLogsBySessionDate(String sessionDate, String userId) {
    final query = _db.select(_db.prayerLogs)
      ..where((l) =>
          l.deleted.equals(0) &
          l.trashedAt.isNull() &
          l.userId.equals(userId) &
          l.sessionDate.equals(sessionDate))
      ..orderBy([(l) => OrderingTerm.desc(l.loggedAt)]);

    return query.watch().map((rows) => rows.map(_toModel).toList());
  }

  /// Watch prayer logs for a specific prayer (reactive stream)
  Stream<List<PrayerLogModel>> watchLogsByPrayer(String prayerId, String userId) {
    final query = _db.select(_db.prayerLogs)
      ..where((l) =>
          l.deleted.equals(0) & l.trashedAt.isNull() & l.userId.equals(userId) & l.prayerId.equals(prayerId))
      ..orderBy([(l) => OrderingTerm.desc(l.loggedAt)]);

    return query.watch().map((rows) => rows.map(_toModel).toList());
  }

  // ==================== WRITE OPERATIONS ====================

  /// Create a new prayer log entry
  Future<PrayerLogModel> logPrayer({
    required String prayerId,
    required String userId,
    String note = '',
    String? sessionDate,
  }) async {
    final log = PrayerLogModel.create(
      id: generateId(),
      prayerId: prayerId,
      userId: userId,
      note: note,
      sessionDate: sessionDate,
    );

    final oplogEntry = createInsertOp(log);

    await _db.transaction(() async {
      await _db.into(_db.prayerLogs).insert(_toCompanion(log));
      await _db.into(_db.oplog).insert(_oplogToCompanion(oplogEntry));
    });

    return log;
  }

  /// Update a prayer log (e.g., add/change note)
  Future<PrayerLogModel> updateLog({
    required String id,
    String? note,
  }) async {
    final existing = await getLogById(id);
    if (existing == null) {
      throw PrayerLogNotFoundException(id);
    }

    final updated = existing.copyWithUpdate(note: note);
    final oplogEntry = createUpdateOp(updated);

    await _db.transaction(() async {
      await (_db.update(_db.prayerLogs)..where((l) => l.id.equals(id)))
          .write(_toCompanion(updated));
      await _db.into(_db.oplog).insert(_oplogToCompanion(oplogEntry));
    });

    return updated;
  }

  /// Soft delete a prayer log
  Future<void> deleteLog(String id) async {
    final existing = await getLogById(id);
    if (existing == null) {
      throw PrayerLogNotFoundException(id);
    }

    final deletedLog = existing.softDelete();
    final oplogEntry = createDeleteOp(deletedLog);

    await _db.transaction(() async {
      await (_db.update(_db.prayerLogs)..where((l) => l.id.equals(id)))
          .write(_toCompanion(deletedLog));
      await _db.into(_db.oplog).insert(_oplogToCompanion(oplogEntry));
    });
  }

  // ==================== HELPER METHODS ====================

  /// Convert database row to domain model
  PrayerLogModel _toModel(PrayerLog row) {
    return PrayerLogModel(
      id: row.id,
      prayerId: row.prayerId,
      userId: row.userId,
      note: row.note,
      loggedAt: row.loggedAt,
      sessionDate: row.sessionDate,
      updatedAt: row.updatedAt,
      version: row.version,
      deleted: row.deleted,
      trashedAt: row.trashedAt,
      createdAt: row.createdAt,
    );
  }

  /// Convert domain model to database companion
  PrayerLogsCompanion _toCompanion(PrayerLogModel model) {
    return PrayerLogsCompanion(
      id: Value(model.id),
      prayerId: Value(model.prayerId),
      userId: Value(model.userId),
      note: Value(model.note),
      loggedAt: Value(model.loggedAt),
      sessionDate: Value(model.sessionDate),
      updatedAt: Value(model.updatedAt),
      version: Value(model.version),
      deleted: Value(model.deleted),
      trashedAt: Value(model.trashedAt),
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

// ==================== EXCEPTIONS ====================

class PrayerLogNotFoundException implements Exception {
  final String logId;
  PrayerLogNotFoundException(this.logId);

  @override
  String toString() => 'Prayer log not found: $logId';
}
