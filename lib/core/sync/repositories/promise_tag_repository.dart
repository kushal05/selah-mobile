import 'package:drift/drift.dart';

import '../../database/sync_database.dart';
import '../models/oplog_entry.dart';
import '../models/promise_tag_model.dart';
import 'base_sync_repository.dart';

/// Repository for promise-tag junction operations (sync-enabled)
///
/// Follows same pattern as NoteTagRepository.
class PromiseTagRepository extends BaseSyncRepository<PromiseTagModel> {
  final SyncDatabase _db;
  final String _deviceId;

  PromiseTagRepository(this._db, this._deviceId);

  @override
  String get deviceId => _deviceId;

  @override
  OplogEntityType get entityType => OplogEntityType.promiseTag;

  // ==================== READ OPERATIONS ====================

  /// Get all tag IDs for a promise
  Future<List<String>> getTagIdsForPromise(String promiseId) async {
    final query = _db.select(_db.syncPromiseTags)
      ..where(
          (pt) => pt.promiseId.equals(promiseId) & pt.deleted.equals(0) & pt.trashedAt.isNull());

    final rows = await query.get();
    return rows.map((r) => r.tagId).toList();
  }

  /// Get all promise-tag associations for a promise
  Future<List<PromiseTagModel>> getTagsForPromise(String promiseId) async {
    final query = _db.select(_db.syncPromiseTags)
      ..where(
          (pt) => pt.promiseId.equals(promiseId) & pt.deleted.equals(0) & pt.trashedAt.isNull());

    final rows = await query.get();
    return rows.map(_toModel).toList();
  }

  /// Watch tag IDs for a promise (reactive)
  Stream<List<String>> watchTagIdsForPromise(String promiseId) {
    final query = _db.select(_db.syncPromiseTags)
      ..where(
          (pt) => pt.promiseId.equals(promiseId) & pt.deleted.equals(0) & pt.trashedAt.isNull());

    return query.watch().map((rows) => rows.map((r) => r.tagId).toList());
  }

  /// Get all promise IDs that have a specific tag
  Future<List<String>> getPromiseIdsWithTag(String tagId) async {
    final query = _db.select(_db.syncPromiseTags)
      ..where((pt) => pt.tagId.equals(tagId) & pt.deleted.equals(0) & pt.trashedAt.isNull());

    final rows = await query.get();
    return rows.map((r) => r.promiseId).toList();
  }

  // ==================== WRITE OPERATIONS ====================

  Future<PromiseTagModel> addTagToPromise({
    required String promiseId,
    required String tagId,
    required String userId,
  }) async {
    // Check for existing (including soft-deleted) to prevent duplicates
    final existing = await (_db.select(_db.syncPromiseTags)
          ..where((pt) =>
              pt.promiseId.equals(promiseId) & pt.tagId.equals(tagId)))
        .getSingleOrNull();

    if (existing != null && existing.deleted == 0) {
      return _toModel(existing);
    }

    final promiseTag = PromiseTagModel.create(
      id: existing?.id ?? generateId(),
      promiseId: promiseId,
      tagId: tagId,
      userId: userId,
    );

    final oplogEntry = createInsertOp(promiseTag);

    await _db.transaction(() async {
      await _db
          .into(_db.syncPromiseTags)
          .insertOnConflictUpdate(_toCompanion(promiseTag));
      await _db.into(_db.oplog).insert(_oplogToCompanion(oplogEntry));
    });

    return promiseTag;
  }

  Future<void> removeTagFromPromise(String promiseId, String tagId) async {
    final query = _db.select(_db.syncPromiseTags)
      ..where((pt) =>
          pt.promiseId.equals(promiseId) &
          pt.tagId.equals(tagId) &
          pt.deleted.equals(0));

    final row = await query.getSingleOrNull();
    if (row == null) return;

    final model = _toModel(row);
    final deleted = model.softDelete();
    final oplogEntry = createDeleteOp(deleted);

    await _db.transaction(() async {
      await (_db.update(_db.syncPromiseTags)
            ..where((pt) => pt.id.equals(model.id)))
          .write(_toCompanion(deleted));
      await _db.into(_db.oplog).insert(_oplogToCompanion(oplogEntry));
    });
  }

  /// Replace all tags for a promise with the given set.
  /// Diffs existing vs desired to minimize oplog entries.
  Future<void> setTagsForPromise(
    String promiseId,
    List<String> tagIds,
    String userId,
  ) async {
    final current = await getTagsForPromise(promiseId);
    final currentTagIds = current.map((pt) => pt.tagId).toSet();
    final desiredTagIds = tagIds.toSet();

    // Tags to add
    final toAdd = desiredTagIds.difference(currentTagIds);
    // Tags to remove
    final toRemove = currentTagIds.difference(desiredTagIds);

    for (final tagId in toAdd) {
      await addTagToPromise(
          promiseId: promiseId, tagId: tagId, userId: userId);
    }
    for (final tagId in toRemove) {
      await removeTagFromPromise(promiseId, tagId);
    }
  }

  // ==================== HELPERS ====================

  PromiseTagModel _toModel(SyncPromiseTag row) {
    return PromiseTagModel(
      id: row.id,
      promiseId: row.promiseId,
      tagId: row.tagId,
      userId: row.userId,
      updatedAt: row.updatedAt,
      version: row.version,
      deleted: row.deleted,
      trashedAt: row.trashedAt,
      createdAt: row.createdAt,
    );
  }

  SyncPromiseTagsCompanion _toCompanion(PromiseTagModel model) {
    return SyncPromiseTagsCompanion(
      id: Value(model.id),
      promiseId: Value(model.promiseId),
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
