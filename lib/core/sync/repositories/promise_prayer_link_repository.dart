import 'package:drift/drift.dart';

import '../../database/sync_database.dart';
import '../models/oplog_entry.dart';
import '../models/promise_prayer_link_model.dart';
import 'base_sync_repository.dart';

/// Repository for promise-prayer link operations (sync-enabled)
///
/// Follows same pattern as PrayerTagRepository / PromiseTagRepository.
class PromisePrayerLinkRepository
    extends BaseSyncRepository<PromisePrayerLinkModel> {
  final SyncDatabase _db;
  final String _deviceId;

  PromisePrayerLinkRepository(this._db, this._deviceId);

  @override
  String get deviceId => _deviceId;

  @override
  OplogEntityType get entityType => OplogEntityType.promisePrayerLink;

  // ==================== READ OPERATIONS ====================

  /// Get all prayer IDs linked to a promise
  Future<List<String>> getLinkedPrayerIds(String promiseId) async {
    final query = _db.select(_db.promisePrayerLinks)
      ..where(
          (l) => l.promiseId.equals(promiseId) & l.deleted.equals(0) & l.trashedAt.isNull());

    final rows = await query.get();
    return rows.map((r) => r.prayerId).toList();
  }

  /// Get all promise IDs linked to a prayer
  Future<List<String>> getLinkedPromiseIds(String prayerId) async {
    final query = _db.select(_db.promisePrayerLinks)
      ..where(
          (l) => l.prayerId.equals(prayerId) & l.deleted.equals(0) & l.trashedAt.isNull());

    final rows = await query.get();
    return rows.map((r) => r.promiseId).toList();
  }

  /// Watch prayer IDs linked to a promise (reactive)
  Stream<List<String>> watchLinkedPrayerIds(String promiseId) {
    final query = _db.select(_db.promisePrayerLinks)
      ..where(
          (l) => l.promiseId.equals(promiseId) & l.deleted.equals(0) & l.trashedAt.isNull());

    return query
        .watch()
        .map((rows) => rows.map((r) => r.prayerId).toList());
  }

  /// Watch promise IDs linked to a prayer (reactive)
  Stream<List<String>> watchLinkedPromiseIds(String prayerId) {
    final query = _db.select(_db.promisePrayerLinks)
      ..where(
          (l) => l.prayerId.equals(prayerId) & l.deleted.equals(0) & l.trashedAt.isNull());

    return query
        .watch()
        .map((rows) => rows.map((r) => r.promiseId).toList());
  }

  // ==================== WRITE OPERATIONS ====================

  /// Link a promise to a prayer
  Future<PromisePrayerLinkModel> linkPromiseToPrayer({
    required String promiseId,
    required String prayerId,
    required String userId,
  }) async {
    // Check for existing (including soft-deleted) to prevent duplicates
    final existing = await (_db.select(_db.promisePrayerLinks)
          ..where((l) =>
              l.promiseId.equals(promiseId) & l.prayerId.equals(prayerId)))
        .getSingleOrNull();

    if (existing != null && existing.deleted == 0) {
      return _toModel(existing);
    }

    final link = PromisePrayerLinkModel.create(
      id: existing?.id ?? generateId(),
      promiseId: promiseId,
      prayerId: prayerId,
      userId: userId,
    );

    final oplogEntry = createInsertOp(link);

    await _db.transaction(() async {
      await _db
          .into(_db.promisePrayerLinks)
          .insertOnConflictUpdate(_toCompanion(link));
      await _db.into(_db.oplog).insert(_oplogToCompanion(oplogEntry));
    });

    return link;
  }

  /// Unlink a promise from a prayer (soft delete)
  Future<void> unlinkPromiseFromPrayer(
      String promiseId, String prayerId) async {
    final query = _db.select(_db.promisePrayerLinks)
      ..where((l) =>
          l.promiseId.equals(promiseId) &
          l.prayerId.equals(prayerId) &
          l.deleted.equals(0));

    final row = await query.getSingleOrNull();
    if (row == null) return;

    final model = _toModel(row);
    final deleted = model.softDelete();
    final oplogEntry = createDeleteOp(deleted);

    await _db.transaction(() async {
      await (_db.update(_db.promisePrayerLinks)
            ..where((l) => l.id.equals(model.id)))
          .write(_toCompanion(deleted));
      await _db.into(_db.oplog).insert(_oplogToCompanion(oplogEntry));
    });
  }

  /// Soft-delete all links for a promise (cascade on promise delete)
  Future<void> softDeleteLinksForPromise(String promiseId) async {
    final query = _db.select(_db.promisePrayerLinks)
      ..where(
          (l) => l.promiseId.equals(promiseId) & l.deleted.equals(0) & l.trashedAt.isNull());

    final rows = await query.get();
    for (final row in rows) {
      final model = _toModel(row);
      final deleted = model.softDelete();
      final oplogEntry = createDeleteOp(deleted);

      await _db.transaction(() async {
        await (_db.update(_db.promisePrayerLinks)
              ..where((l) => l.id.equals(model.id)))
            .write(_toCompanion(deleted));
        await _db.into(_db.oplog).insert(_oplogToCompanion(oplogEntry));
      });
    }
  }

  /// Soft-delete all links for a prayer (cascade on prayer delete)
  Future<void> softDeleteLinksForPrayer(String prayerId) async {
    final query = _db.select(_db.promisePrayerLinks)
      ..where(
          (l) => l.prayerId.equals(prayerId) & l.deleted.equals(0) & l.trashedAt.isNull());

    final rows = await query.get();
    for (final row in rows) {
      final model = _toModel(row);
      final deleted = model.softDelete();
      final oplogEntry = createDeleteOp(deleted);

      await _db.transaction(() async {
        await (_db.update(_db.promisePrayerLinks)
              ..where((l) => l.id.equals(model.id)))
            .write(_toCompanion(deleted));
        await _db.into(_db.oplog).insert(_oplogToCompanion(oplogEntry));
      });
    }
  }

  // ==================== HELPERS ====================

  PromisePrayerLinkModel _toModel(PromisePrayerLink row) {
    return PromisePrayerLinkModel(
      id: row.id,
      promiseId: row.promiseId,
      prayerId: row.prayerId,
      userId: row.userId,
      updatedAt: row.updatedAt,
      version: row.version,
      deleted: row.deleted,
      trashedAt: row.trashedAt,
      createdAt: row.createdAt,
    );
  }

  PromisePrayerLinksCompanion _toCompanion(PromisePrayerLinkModel model) {
    return PromisePrayerLinksCompanion(
      id: Value(model.id),
      promiseId: Value(model.promiseId),
      prayerId: Value(model.prayerId),
      userId: Value(model.userId),
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
