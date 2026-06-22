import 'package:drift/drift.dart';

import '../../database/sync_database.dart';
import '../models/oplog_entry.dart';
import '../models/prayer_tag_model.dart';
import 'base_sync_repository.dart';

/// Repository for prayer-tag junction operations (sync-enabled)
///
/// Follows same pattern as NoteTagRepository / PromiseTagRepository.
class PrayerTagRepository extends BaseSyncRepository<PrayerTagModel> {
  final SyncDatabase _db;
  final String _deviceId;

  PrayerTagRepository(this._db, this._deviceId);

  @override
  String get deviceId => _deviceId;

  @override
  OplogEntityType get entityType => OplogEntityType.prayerTag;

  // ==================== READ OPERATIONS ====================

  /// Get all tag IDs for a prayer
  Future<List<String>> getTagIdsForPrayer(String prayerId) async {
    final query = _db.select(_db.syncPrayerTags)
      ..where(
          (pt) => pt.prayerId.equals(prayerId) & pt.deleted.equals(0) & pt.trashedAt.isNull());

    final rows = await query.get();
    return rows.map((r) => r.tagId).toList();
  }

  /// Get all prayer-tag associations for a prayer
  Future<List<PrayerTagModel>> getTagsForPrayer(String prayerId) async {
    final query = _db.select(_db.syncPrayerTags)
      ..where(
          (pt) => pt.prayerId.equals(prayerId) & pt.deleted.equals(0) & pt.trashedAt.isNull());

    final rows = await query.get();
    return rows.map(_toModel).toList();
  }

  /// Watch tag IDs for a prayer (reactive)
  Stream<List<String>> watchTagIdsForPrayer(String prayerId) {
    final query = _db.select(_db.syncPrayerTags)
      ..where(
          (pt) => pt.prayerId.equals(prayerId) & pt.deleted.equals(0) & pt.trashedAt.isNull());

    return query.watch().map((rows) => rows.map((r) => r.tagId).toList());
  }

  /// Get all prayer IDs that have a specific tag
  Future<List<String>> getPrayerIdsWithTag(String tagId) async {
    final query = _db.select(_db.syncPrayerTags)
      ..where((pt) => pt.tagId.equals(tagId) & pt.deleted.equals(0) & pt.trashedAt.isNull());

    final rows = await query.get();
    return rows.map((r) => r.prayerId).toList();
  }

  // ==================== WRITE OPERATIONS ====================

  Future<PrayerTagModel> addTagToPrayer({
    required String prayerId,
    required String tagId,
    required String userId,
  }) async {
    // Check for existing (including soft-deleted) to prevent duplicates
    final existing = await (_db.select(_db.syncPrayerTags)
          ..where((pt) =>
              pt.prayerId.equals(prayerId) & pt.tagId.equals(tagId)))
        .getSingleOrNull();

    if (existing != null && existing.deleted == 0) {
      return _toModel(existing);
    }

    final prayerTag = PrayerTagModel.create(
      id: existing?.id ?? generateId(),
      prayerId: prayerId,
      tagId: tagId,
      userId: userId,
    );

    final oplogEntry = createInsertOp(prayerTag);

    await _db.transaction(() async {
      await _db
          .into(_db.syncPrayerTags)
          .insertOnConflictUpdate(_toCompanion(prayerTag));
      await _db.into(_db.oplog).insert(_oplogToCompanion(oplogEntry));
    });

    return prayerTag;
  }

  Future<void> removeTagFromPrayer(String prayerId, String tagId) async {
    final query = _db.select(_db.syncPrayerTags)
      ..where((pt) =>
          pt.prayerId.equals(prayerId) &
          pt.tagId.equals(tagId) &
          pt.deleted.equals(0));

    final row = await query.getSingleOrNull();
    if (row == null) return;

    final model = _toModel(row);
    final deleted = model.softDelete();
    final oplogEntry = createDeleteOp(deleted);

    await _db.transaction(() async {
      await (_db.update(_db.syncPrayerTags)
            ..where((pt) => pt.id.equals(model.id)))
          .write(_toCompanion(deleted));
      await _db.into(_db.oplog).insert(_oplogToCompanion(oplogEntry));
    });
  }

  /// Replace all tags for a prayer with the given set.
  Future<void> setTagsForPrayer(
    String prayerId,
    List<String> tagIds,
    String userId,
  ) async {
    final current = await getTagsForPrayer(prayerId);
    final currentTagIds = current.map((pt) => pt.tagId).toSet();
    final desiredTagIds = tagIds.toSet();

    final toAdd = desiredTagIds.difference(currentTagIds);
    final toRemove = currentTagIds.difference(desiredTagIds);

    for (final tagId in toAdd) {
      await addTagToPrayer(
          prayerId: prayerId, tagId: tagId, userId: userId);
    }
    for (final tagId in toRemove) {
      await removeTagFromPrayer(prayerId, tagId);
    }
  }

  // ==================== HELPERS ====================

  PrayerTagModel _toModel(SyncPrayerTag row) {
    return PrayerTagModel(
      id: row.id,
      prayerId: row.prayerId,
      tagId: row.tagId,
      userId: row.userId,
      updatedAt: row.updatedAt,
      version: row.version,
      deleted: row.deleted,
      trashedAt: row.trashedAt,
      createdAt: row.createdAt,
    );
  }

  SyncPrayerTagsCompanion _toCompanion(PrayerTagModel model) {
    return SyncPrayerTagsCompanion(
      id: Value(model.id),
      prayerId: Value(model.prayerId),
      tagId: Value(model.tagId),
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
