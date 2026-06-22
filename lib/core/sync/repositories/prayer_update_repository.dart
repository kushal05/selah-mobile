import 'package:drift/drift.dart';

import '../../database/sync_database.dart';
import '../models/oplog_entry.dart';
import '../models/prayer_update_model.dart';
import 'base_sync_repository.dart';

/// Repository for prayer update operations
///
/// Per spec: Every write is transactional with oplog entry
class PrayerUpdateRepository extends BaseSyncRepository<PrayerUpdateModel> {
  final SyncDatabase _db;
  final String _deviceId;

  PrayerUpdateRepository(this._db, this._deviceId);

  @override
  String get deviceId => _deviceId;

  @override
  OplogEntityType get entityType => OplogEntityType.prayerUpdate;

  // ==================== READ OPERATIONS ====================

  /// Get all updates for a prayer (newest first)
  Future<List<PrayerUpdateModel>> getUpdatesByPrayer(String prayerId) async {
    final query = _db.select(_db.prayerUpdates)
      ..where(
          (u) => u.deleted.equals(0) & u.trashedAt.isNull() & u.prayerId.equals(prayerId))
      ..orderBy([(u) => OrderingTerm.desc(u.createdAt)]);

    final rows = await query.get();
    return rows.map(_toModel).toList();
  }

  /// Watch updates for a prayer (reactive stream, newest first)
  Stream<List<PrayerUpdateModel>> watchUpdatesByPrayer(String prayerId) {
    final query = _db.select(_db.prayerUpdates)
      ..where(
          (u) => u.deleted.equals(0) & u.trashedAt.isNull() & u.prayerId.equals(prayerId))
      ..orderBy([(u) => OrderingTerm.desc(u.createdAt)]);

    return query.watch().map((rows) => rows.map(_toModel).toList());
  }

  /// Watch all updates across all prayers for a user (newest first)
  Stream<List<PrayerUpdateModel>> watchAllUpdates(String userId) {
    final query = _db.select(_db.prayerUpdates)
      ..where((u) => u.deleted.equals(0) & u.trashedAt.isNull() & u.userId.equals(userId))
      ..orderBy([(u) => OrderingTerm.desc(u.createdAt)]);

    return query.watch().map((rows) => rows.map(_toModel).toList());
  }

  /// Get a single update by ID
  Future<PrayerUpdateModel?> getUpdateById(String id) async {
    final query = _db.select(_db.prayerUpdates)
      ..where((u) => u.id.equals(id));

    final row = await query.getSingleOrNull();
    return row != null ? _toModel(row) : null;
  }

  // ==================== WRITE OPERATIONS ====================

  /// Create a new prayer update
  Future<PrayerUpdateModel> addUpdate({
    required String prayerId,
    required String userId,
    required String content,
  }) async {
    final update = PrayerUpdateModel.create(
      id: generateId(),
      prayerId: prayerId,
      userId: userId,
      content: content,
    );

    final oplogEntry = createInsertOp(update);

    await _db.transaction(() async {
      await _db.into(_db.prayerUpdates).insert(_toCompanion(update));
      await _db.into(_db.oplog).insert(_oplogToCompanion(oplogEntry));
    });

    return update;
  }

  /// Soft delete a prayer update
  Future<void> deleteUpdate(String id) async {
    final existing = await getUpdateById(id);
    if (existing == null) {
      throw PrayerUpdateNotFoundException(id);
    }

    final deleted = existing.softDelete();
    final oplogEntry = createDeleteOp(deleted);

    await _db.transaction(() async {
      await (_db.update(_db.prayerUpdates)..where((u) => u.id.equals(id)))
          .write(_toCompanion(deleted));
      await _db.into(_db.oplog).insert(_oplogToCompanion(oplogEntry));
    });
  }

  // ==================== HELPER METHODS ====================

  PrayerUpdateModel _toModel(PrayerUpdate row) {
    return PrayerUpdateModel(
      id: row.id,
      prayerId: row.prayerId,
      userId: row.userId,
      content: row.content,
      updatedAt: row.updatedAt,
      version: row.version,
      deleted: row.deleted,
      trashedAt: row.trashedAt,
      createdAt: row.createdAt,
    );
  }

  PrayerUpdatesCompanion _toCompanion(PrayerUpdateModel model) {
    return PrayerUpdatesCompanion(
      id: Value(model.id),
      prayerId: Value(model.prayerId),
      userId: Value(model.userId),
      content: Value(model.content),
      updatedAt: Value(model.updatedAt),
      version: Value(model.version),
      deleted: Value(model.deleted),
      trashedAt: Value(model.trashedAt),
      createdAt: Value(model.createdAt),
    );
  }

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

class PrayerUpdateNotFoundException implements Exception {
  final String updateId;
  PrayerUpdateNotFoundException(this.updateId);

  @override
  String toString() => 'Prayer update not found: $updateId';
}
