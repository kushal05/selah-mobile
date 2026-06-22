import 'package:drift/drift.dart';

import '../../database/sync_database.dart';
import '../models/oplog_entry.dart';
import '../models/promise_condition_model.dart';
import 'base_sync_repository.dart';

/// Repository for promise condition operations (sync-enabled)
///
/// Per spec: Every write is transactional with oplog entry
class PromiseConditionRepository
    extends BaseSyncRepository<PromiseConditionModel> {
  final SyncDatabase _db;
  final String _deviceId;

  PromiseConditionRepository(this._db, this._deviceId);

  @override
  String get deviceId => _deviceId;

  @override
  OplogEntityType get entityType => OplogEntityType.promiseCondition;

  // ==================== READ OPERATIONS ====================

  /// Get all conditions for a promise
  Future<List<PromiseConditionModel>> getConditionsForPromise(
      String promiseId) async {
    final query = _db.select(_db.promiseConditions)
      ..where(
          (c) => c.promiseId.equals(promiseId) & c.deleted.equals(0) & c.trashedAt.isNull())
      ..orderBy([(c) => OrderingTerm.asc(c.createdAt)]);

    final rows = await query.get();
    return rows.map(_toModel).toList();
  }

  /// Watch all conditions for a promise (reactive stream)
  Stream<List<PromiseConditionModel>> watchConditionsForPromise(
      String promiseId) {
    final query = _db.select(_db.promiseConditions)
      ..where(
          (c) => c.promiseId.equals(promiseId) & c.deleted.equals(0) & c.trashedAt.isNull())
      ..orderBy([(c) => OrderingTerm.asc(c.createdAt)]);

    return query.watch().map((rows) => rows.map(_toModel).toList());
  }

  /// Get a single condition by ID
  Future<PromiseConditionModel?> getConditionById(String id) async {
    final query = _db.select(_db.promiseConditions)
      ..where((c) => c.id.equals(id));

    final row = await query.getSingleOrNull();
    return row != null ? _toModel(row) : null;
  }

  // ==================== WRITE OPERATIONS ====================

  /// Add a new condition to a promise
  Future<PromiseConditionModel> addCondition({
    required String promiseId,
    required String userId,
    required String description,
    String notes = '',
    PromiseConditionStatus status = PromiseConditionStatus.active,
  }) async {
    final condition = PromiseConditionModel.create(
      id: generateId(),
      promiseId: promiseId,
      userId: userId,
      description: description,
      notes: notes,
      status: status,
    );

    final oplogEntry = createInsertOp(condition);

    await _db.transaction(() async {
      await _db
          .into(_db.promiseConditions)
          .insert(_toCompanion(condition));
      await _db.into(_db.oplog).insert(_oplogToCompanion(oplogEntry));
    });

    return condition;
  }

  /// Update an existing condition
  Future<PromiseConditionModel> updateCondition({
    required String id,
    String? description,
    String? notes,
    PromiseConditionStatus? status,
  }) async {
    final existing = await getConditionById(id);
    if (existing == null) {
      throw PromiseConditionNotFoundException(id);
    }

    final updated = existing.copyWithUpdate(
      description: description,
      notes: notes,
      status: status,
    );

    final oplogEntry = createUpdateOp(updated);

    await _db.transaction(() async {
      await (_db.update(_db.promiseConditions)
            ..where((c) => c.id.equals(id)))
          .write(_toCompanion(updated));
      await _db.into(_db.oplog).insert(_oplogToCompanion(oplogEntry));
    });

    return updated;
  }

  /// Soft delete a condition
  Future<void> deleteCondition(String id) async {
    final existing = await getConditionById(id);
    if (existing == null) {
      throw PromiseConditionNotFoundException(id);
    }

    final deleted = existing.softDelete();
    final oplogEntry = createDeleteOp(deleted);

    await _db.transaction(() async {
      await (_db.update(_db.promiseConditions)
            ..where((c) => c.id.equals(id)))
          .write(_toCompanion(deleted));
      await _db.into(_db.oplog).insert(_oplogToCompanion(oplogEntry));
    });
  }

  // ==================== HELPERS ====================

  PromiseConditionModel _toModel(PromiseCondition row) {
    return PromiseConditionModel(
      id: row.id,
      promiseId: row.promiseId,
      userId: row.userId,
      description: row.description,
      notes: row.notes,
      status: PromiseConditionStatus.fromDbValue(row.status),
      updatedAt: row.updatedAt,
      version: row.version,
      deleted: row.deleted,
      trashedAt: row.trashedAt,
      createdAt: row.createdAt,
    );
  }

  PromiseConditionsCompanion _toCompanion(PromiseConditionModel model) {
    return PromiseConditionsCompanion(
      id: Value(model.id),
      promiseId: Value(model.promiseId),
      userId: Value(model.userId),
      description: Value(model.description),
      notes: Value(model.notes),
      status: Value(model.status.toDbValue()),
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

// ==================== EXCEPTIONS ====================

class PromiseConditionNotFoundException implements Exception {
  final String conditionId;
  PromiseConditionNotFoundException(this.conditionId);

  @override
  String toString() => 'Promise condition not found: $conditionId';
}
