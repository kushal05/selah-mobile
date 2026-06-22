import 'package:drift/drift.dart';

import '../../database/sync_database.dart';
import '../models/oplog_entry.dart';
import '../models/promise_model.dart';
import 'base_sync_repository.dart';
import 'entity_access_repository.dart';
import 'promise_prayer_link_repository.dart';

/// Repository for promise (Bible verse) operations
///
/// Per spec: Every write is transactional with oplog entry
class PromiseRepository extends BaseSyncRepository<PromiseModel> {
  final SyncDatabase _db;
  final String _deviceId;
  final EntityAccessRepository _entityAccessRepo;
  PromisePrayerLinkRepository? _linkRepository;

  PromiseRepository(this._db, this._deviceId, this._entityAccessRepo);

  /// Set the link repository for cascade deletes.
  /// Injected after construction to avoid circular dependencies.
  set linkRepository(PromisePrayerLinkRepository repo) =>
      _linkRepository = repo;

  @override
  String get deviceId => _deviceId;

  @override
  OplogEntityType get entityType => OplogEntityType.promise;

  // ==================== READ OPERATIONS ====================

  /// Get all promises (non-deleted, non-trashed) for a user
  Future<List<PromiseModel>> getAllPromises(String userId) async {
    final query = _db.select(_db.promises)
      ..where((p) => p.deleted.equals(0) & p.userId.equals(userId) & p.trashedAt.isNull())
      ..orderBy([(p) => OrderingTerm.desc(p.updatedAt)]);

    final rows = await query.get();
    return rows.map(_toModel).toList();
  }

  /// Get favorite promises for a user
  Future<List<PromiseModel>> getFavoritePromises(String userId) async {
    final query = _db.select(_db.promises)
      ..where((p) => p.deleted.equals(0) & p.userId.equals(userId) & p.trashedAt.isNull() & p.isFavorite.equals(1))
      ..orderBy([(p) => OrderingTerm.desc(p.updatedAt)]);

    final rows = await query.get();
    return rows.map(_toModel).toList();
  }

  /// Get promise by ID
  Future<PromiseModel?> getPromiseById(String id) async {
    final query = _db.select(_db.promises)..where((p) => p.id.equals(id));

    final row = await query.getSingleOrNull();
    return row != null ? _toModel(row) : null;
  }

  /// Watch all promises (reactive stream) for a user
  Stream<List<PromiseModel>> watchAllPromises(String userId) {
    final query = _db.select(_db.promises)
      ..where((p) => p.deleted.equals(0) & p.userId.equals(userId) & p.trashedAt.isNull())
      ..orderBy([(p) => OrderingTerm.desc(p.updatedAt)]);

    return query.watch().map((rows) => rows.map(_toModel).toList());
  }

  /// Watch favorite promises for a user
  Stream<List<PromiseModel>> watchFavoritePromises(String userId) {
    final query = _db.select(_db.promises)
      ..where((p) => p.deleted.equals(0) & p.userId.equals(userId) & p.trashedAt.isNull() & p.isFavorite.equals(1))
      ..orderBy([(p) => OrderingTerm.desc(p.updatedAt)]);

    return query.watch().map((rows) => rows.map(_toModel).toList());
  }

  /// Search promises by reference or content for a user
  Future<List<PromiseModel>> searchPromises(String searchQuery, String userId) async {
    final searchPattern = '%$searchQuery%';
    final rows = await _db.customSelect(
      'SELECT * FROM promises '
      'WHERE deleted = 0 AND trashed_at IS NULL AND user_id = ? '
      'AND (reference LIKE ? OR content LIKE ? OR notes LIKE ? OR category LIKE ?) '
      'ORDER BY updated_at DESC',
      variables: [
        Variable.withString(userId),
        Variable.withString(searchPattern),
        Variable.withString(searchPattern),
        Variable.withString(searchPattern),
        Variable.withString(searchPattern),
      ],
    ).get();
    return rows.map((row) {
      return PromiseModel(
        id: row.read<String>('id'),
        userId: row.read<String>('user_id'),
        reference: row.read<String>('reference'),
        content: row.read<String>('content'),
        preview: row.read<String>('preview'),
        notes: row.read<String>('notes'),
        category: row.readNullable<String>('category'),
        isFavorite: row.read<int>('is_favorite') == 1,
        updatedAt: row.read<int>('updated_at'),
        version: row.read<int>('version'),
        deleted: row.read<int>('deleted'),
        trashedAt: row.readNullable<int>('trashed_at'),
        createdAt: row.read<int>('created_at'),
      );
    }).toList();
  }

  /// Get promise count for a user
  Future<int> getPromiseCount(String userId) async {
    final result = await _db.customSelect(
      'SELECT COUNT(*) as count FROM promises WHERE user_id = ? AND deleted = 0 AND trashed_at IS NULL',
      variables: [Variable.withString(userId)],
    ).getSingle();
    return result.read<int>('count');
  }

  // ==================== WRITE OPERATIONS ====================

  /// Create a new promise
  Future<PromiseModel> createPromise({
    required String userId,
    required String reference,
    required String content,
    String? preview,
    String notes = '',
    String? category,
    bool isFavorite = false,
  }) async {
    final promise = PromiseModel.create(
      id: generateId(),
      userId: userId,
      reference: reference,
      content: content,
      preview: preview,
      notes: notes,
      category: category,
      isFavorite: isFavorite,
    );

    final oplogEntry = createInsertOp(promise);

    await _db.transaction(() async {
      await _db.into(_db.promises).insert(_toCompanion(promise));
      await _db.into(_db.oplog).insert(_oplogToCompanion(oplogEntry));
    });

    return promise;
  }

  /// Update a promise
  Future<PromiseModel> updatePromise({
    required String id,
    String? reference,
    String? content,
    String? preview,
    String? notes,
    String? category,
    bool? isFavorite,
  }) async {
    final existing = await getPromiseById(id);
    if (existing == null) {
      throw PromiseNotFoundException(id);
    }

    final updated = existing.copyWithUpdate(
      reference: reference,
      content: content,
      preview: preview,
      notes: notes,
      category: category,
      isFavorite: isFavorite,
    );

    final oplogEntry = createUpdateOp(updated);

    await _db.transaction(() async {
      await (_db.update(_db.promises)..where((p) => p.id.equals(id)))
          .write(_toCompanion(updated));
      await _db.into(_db.oplog).insert(_oplogToCompanion(oplogEntry));
    });

    return updated;
  }

  /// Toggle favorite status
  Future<PromiseModel> toggleFavorite(String id) async {
    final existing = await getPromiseById(id);
    if (existing == null) {
      throw PromiseNotFoundException(id);
    }

    final updated = existing.toggleFavorite();
    final oplogEntry = createUpdateOp(updated);

    await _db.transaction(() async {
      await (_db.update(_db.promises)..where((p) => p.id.equals(id)))
          .write(_toCompanion(updated));
      await _db.into(_db.oplog).insert(_oplogToCompanion(oplogEntry));
    });

    return updated;
  }

  /// Soft delete a promise
  Future<void> deletePromise(String id) async {
    final existing = await getPromiseById(id);
    if (existing == null) {
      throw PromiseNotFoundException(id);
    }

    final deletedPromise = existing.softDelete();
    final oplogEntry = createDeleteOp(deletedPromise);

    await _db.transaction(() async {
      await (_db.update(_db.promises)..where((p) => p.id.equals(id)))
          .write(_toCompanion(deletedPromise));
      await _db.into(_db.oplog).insert(_oplogToCompanion(oplogEntry));
    });

    // Cascade: soft-delete all promise-prayer links
    await _linkRepository?.softDeleteLinksForPromise(id);

    // Cascade: revoke entity_access grants for this promise so recipients'
    // local DBs drop their stale access rows on next sync.
    await _entityAccessRepo.deleteAllAccessForEntity('promise', id);
  }

  // ==================== TRASH OPERATIONS ====================

  /// Move promise to trash
  Future<PromiseModel> trashPromise(String id) async {
    final existing = await getPromiseById(id);
    if (existing == null) throw PromiseNotFoundException(id);

    final trashed = existing.moveToTrash();
    final oplogEntry = createUpdateOp(trashed);

    await _db.transaction(() async {
      await (_db.update(_db.promises)..where((p) => p.id.equals(id)))
          .write(_toCompanion(trashed));
      await _db.into(_db.oplog).insert(_oplogToCompanion(oplogEntry));
    });

    return trashed;
  }

  /// Restore promise from trash
  Future<PromiseModel> restorePromise(String id) async {
    final existing = await getPromiseById(id);
    if (existing == null) throw PromiseNotFoundException(id);

    final restored = existing.restoreFromTrash();
    final oplogEntry = createUpdateOp(restored);

    await _db.transaction(() async {
      await (_db.update(_db.promises)..where((p) => p.id.equals(id)))
          .write(_toCompanion(restored));
      await _db.into(_db.oplog).insert(_oplogToCompanion(oplogEntry));
    });

    return restored;
  }

  /// Get all trashed promises for a user
  Future<List<PromiseModel>> getTrashedPromises(String userId) async {
    final query = _db.select(_db.promises)
      ..where((p) => p.userId.equals(userId) & p.deleted.equals(0) & p.trashedAt.isNotNull())
      ..orderBy([(p) => OrderingTerm.desc(p.trashedAt)]);
    final rows = await query.get();
    return rows.map(_toModel).toList();
  }

  /// Watch trashed promises for a user
  Stream<List<PromiseModel>> watchTrashedPromises(String userId) {
    final query = _db.select(_db.promises)
      ..where((p) => p.userId.equals(userId) & p.deleted.equals(0) & p.trashedAt.isNotNull())
      ..orderBy([(p) => OrderingTerm.desc(p.trashedAt)]);
    return query.watch().map((rows) => rows.map(_toModel).toList());
  }

  // ==================== HELPER METHODS ====================

  /// Convert database row to domain model
  PromiseModel _toModel(Promise row) {
    return PromiseModel(
      id: row.id,
      userId: row.userId,
      reference: row.reference,
      content: row.content,
      preview: row.preview,
      notes: row.notes,
      category: row.category,
      isFavorite: row.isFavorite == 1,
      updatedAt: row.updatedAt,
      version: row.version,
      deleted: row.deleted,
      trashedAt: row.trashedAt,
      createdAt: row.createdAt,
    );
  }

  /// Convert domain model to database companion
  PromisesCompanion _toCompanion(PromiseModel model) {
    return PromisesCompanion(
      id: Value(model.id),
      userId: Value(model.userId),
      reference: Value(model.reference),
      content: Value(model.content),
      preview: Value(model.preview),
      notes: Value(model.notes),
      category: Value(model.category),
      isFavorite: Value(model.isFavorite ? 1 : 0),
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

class PromiseNotFoundException implements Exception {
  final String promiseId;
  PromiseNotFoundException(this.promiseId);

  @override
  String toString() => 'Promise not found: $promiseId';
}
