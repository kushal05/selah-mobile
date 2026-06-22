import 'package:drift/drift.dart';

import '../../database/sync_database.dart';
import '../models/entity_access_model.dart';
import '../models/oplog_entry.dart';
import 'base_sync_repository.dart';

/// Repository for universal access control with oplog-based sync.
///
/// Every write creates an oplog entry in a transaction, following
/// the same pattern as all other sync-enabled repositories.
class EntityAccessRepository extends BaseSyncRepository<EntityAccessModel> {
  final SyncDatabase _db;
  final String _deviceId;

  EntityAccessRepository(this._db, this._deviceId);

  @override
  String get deviceId => _deviceId;

  @override
  OplogEntityType get entityType => OplogEntityType.entityAccess;

  // ==================== READ OPERATIONS ====================

  Future<EntityAccessModel?> getById(String id) async {
    final row = await (_db.select(_db.entityAccess)
          ..where((e) => e.id.equals(id)))
        .getSingleOrNull();
    return row != null ? _toModel(row) : null;
  }

  /// Get all non-deleted access records for a specific entity.
  Future<List<EntityAccessModel>> getAccessForEntity(
    String entityType,
    String entityId,
  ) async {
    final query = _db.select(_db.entityAccess)
      ..where((e) =>
          e.entityType.equals(entityType) &
          e.entityId.equals(entityId) &
          e.deleted.equals(0));
    final rows = await query.get();
    return rows.map(_toModel).toList();
  }

  /// Watch access records for a specific entity (reactive).
  Stream<List<EntityAccessModel>> watchAccessForEntity(
    String entityType,
    String entityId,
  ) {
    final query = _db.select(_db.entityAccess)
      ..where((e) =>
          e.entityType.equals(entityType) &
          e.entityId.equals(entityId) &
          e.deleted.equals(0));
    return query.watch().map((rows) => rows.map(_toModel).toList());
  }

  /// Get all access records owned by a user for a specific entity type.
  Future<List<EntityAccessModel>> getAccessByUserAndType(
    String userId,
    String entityType,
  ) async {
    final query = _db.select(_db.entityAccess)
      ..where((e) =>
          e.userId.equals(userId) &
          e.entityType.equals(entityType) &
          e.deleted.equals(0));
    final rows = await query.get();
    return rows.map(_toModel).toList();
  }

  /// Get all entities shared with a specific group.
  Future<List<EntityAccessModel>> getAccessForGroup(String groupId) async {
    final query = _db.select(_db.entityAccess)
      ..where((e) =>
          e.accessType.equals('group') &
          e.targetId.equals(groupId) &
          e.deleted.equals(0));
    final rows = await query.get();
    return rows.map(_toModel).toList();
  }

  /// Watch all entities shared with a specific group (reactive).
  Stream<List<EntityAccessModel>> watchAccessForGroup(String groupId) {
    final query = _db.select(_db.entityAccess)
      ..where((e) =>
          e.accessType.equals('group') &
          e.targetId.equals(groupId) &
          e.deleted.equals(0));
    return query.watch().map((rows) => rows.map(_toModel).toList());
  }

  /// Watch pending tier-2 user shares addressed to the given userId.
  /// Pending = acceptedAt is null, deleted = 0, access_type = 'user'.
  /// Order: newest-first so recent invites surface at the top of the inbox.
  Stream<List<EntityAccessModel>> watchPendingSharesForTarget(String userId) {
    final query = _db.select(_db.entityAccess)
      ..where((e) =>
          e.accessType.equals('user') &
          e.targetId.equals(userId) &
          e.acceptedAt.isNull() &
          e.deleted.equals(0))
      ..orderBy([(e) => OrderingTerm.desc(e.createdAt)]);
    return query.watch().map((rows) => rows.map(_toModel).toList());
  }

  /// Watch accepted tier-2 user shares the current user has incoming.
  Stream<List<EntityAccessModel>> watchAcceptedSharesForTarget(String userId) {
    final query = _db.select(_db.entityAccess)
      ..where((e) =>
          e.accessType.equals('user') &
          e.targetId.equals(userId) &
          e.acceptedAt.isNotNull() &
          e.deleted.equals(0))
      ..orderBy([(e) => OrderingTerm.desc(e.acceptedAt)]);
    return query.watch().map((rows) => rows.map(_toModel).toList());
  }

  /// Get all access records for a user (all entity types).
  Future<List<EntityAccessModel>> getAllAccessForUser(String userId) async {
    final query = _db.select(_db.entityAccess)
      ..where((e) => e.userId.equals(userId) & e.deleted.equals(0))
      ..orderBy([(e) => OrderingTerm.desc(e.updatedAt)]);
    final rows = await query.get();
    return rows.map(_toModel).toList();
  }

  // ==================== WRITE OPERATIONS ====================

  /// Create a new access record.
  Future<EntityAccessModel> createAccess(EntityAccessModel access) async {
    final oplogEntry = createInsertOp(access);

    await _db.transaction(() async {
      await _db.into(_db.entityAccess).insert(_toCompanion(access));
      await _db.into(_db.oplog).insert(_oplogToCompanion(oplogEntry));
    });

    return access;
  }

  /// Update the role on an access record.
  Future<EntityAccessModel> updateAccessRole(
    String id,
    AccessRole newRole,
  ) async {
    final existing = await getById(id);
    if (existing == null) {
      throw EntityAccessNotFoundException(id);
    }

    final updated = existing.copyWithUpdate(role: newRole);
    final oplogEntry = createUpdateOp(updated);

    await _db.transaction(() async {
      await (_db.update(_db.entityAccess)..where((e) => e.id.equals(id)))
          .write(_toCompanion(updated));
      await _db.into(_db.oplog).insert(_oplogToCompanion(oplogEntry));
    });

    return updated;
  }

  /// Accept a pending tier-2 user share. No-op if already accepted.
  Future<EntityAccessModel> acceptAccess(String id) async {
    final existing = await getById(id);
    if (existing == null) {
      throw EntityAccessNotFoundException(id);
    }
    if (existing.isAccepted) return existing;

    final accepted = existing.accept();
    final oplogEntry = createUpdateOp(accepted);

    await _db.transaction(() async {
      await (_db.update(_db.entityAccess)..where((e) => e.id.equals(id)))
          .write(_toCompanion(accepted));
      await _db.into(_db.oplog).insert(_oplogToCompanion(oplogEntry));
    });

    return accepted;
  }

  /// Soft-delete an access record (revoke access).
  Future<void> deleteAccess(String id) async {
    final existing = await getById(id);
    if (existing == null) {
      throw EntityAccessNotFoundException(id);
    }

    final deleted = existing.softDelete();
    final oplogEntry = createDeleteOp(deleted);

    await _db.transaction(() async {
      await (_db.update(_db.entityAccess)..where((e) => e.id.equals(id)))
          .write(_toCompanion(deleted));
      await _db.into(_db.oplog).insert(_oplogToCompanion(oplogEntry));
    });
  }

  /// Remove all non-owner access records for an entity (when changing sharing mode).
  /// All deletes + oplog entries are batched in a single transaction.
  Future<void> deleteAllNonOwnerAccess(
    String entityType,
    String entityId,
  ) async {
    final records = await getAccessForEntity(entityType, entityId);
    final nonOwner = records.where((r) => r.accessType != AccessType.owner).toList();
    if (nonOwner.isEmpty) return;

    await _db.transaction(() async {
      for (final record in nonOwner) {
        final deleted = record.softDelete();
        final oplogEntry = createDeleteOp(deleted);
        await (_db.update(_db.entityAccess)
              ..where((e) => e.id.equals(record.id)))
            .write(_toCompanion(deleted));
        await _db.into(_db.oplog).insert(_oplogToCompanion(oplogEntry));
      }
    });
  }

  /// Remove all access records for an entity (when entity is deleted).
  /// All deletes + oplog entries are batched in a single transaction.
  Future<void> deleteAllAccessForEntity(
    String entityType,
    String entityId,
  ) async {
    final records = await getAccessForEntity(entityType, entityId);
    if (records.isEmpty) return;

    await _db.transaction(() async {
      for (final record in records) {
        final deleted = record.softDelete();
        final oplogEntry = createDeleteOp(deleted);
        await (_db.update(_db.entityAccess)
              ..where((e) => e.id.equals(record.id)))
            .write(_toCompanion(deleted));
        await _db.into(_db.oplog).insert(_oplogToCompanion(oplogEntry));
      }
    });
  }

  /// Batch-insert access records without oplog (for migration only).
  /// This should only be used during the v21 data migration.
  Future<void> insertMigrationBatch(List<EntityAccessModel> records) async {
    await _db.batch((batch) {
      for (final record in records) {
        batch.insert(_db.entityAccess, _toCompanion(record));
      }
    });
  }

  // ==================== HELPER METHODS ====================

  EntityAccessModel _toModel(EntityAccessData row) {
    return EntityAccessModel(
      id: row.id,
      entityType: row.entityType,
      entityId: row.entityId,
      accessType: AccessType.fromDbValue(row.accessType),
      targetId: row.targetId,
      role: AccessRole.fromDbValue(row.role),
      userId: row.userId,
      updatedAt: row.updatedAt,
      version: row.version,
      deleted: row.deleted,
      createdAt: row.createdAt,
      acceptedAt: row.acceptedAt,
    );
  }

  EntityAccessCompanion _toCompanion(EntityAccessModel model) {
    return EntityAccessCompanion(
      id: Value(model.id),
      entityType: Value(model.entityType),
      entityId: Value(model.entityId),
      accessType: Value(model.accessType.toDbValue()),
      targetId: Value(model.targetId),
      role: Value(model.role.toDbValue()),
      userId: Value(model.userId),
      updatedAt: Value(model.updatedAt),
      version: Value(model.version),
      deleted: Value(model.deleted),
      createdAt: Value(model.createdAt),
      acceptedAt: Value(model.acceptedAt),
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

class EntityAccessNotFoundException implements Exception {
  final String accessId;
  EntityAccessNotFoundException(this.accessId);

  @override
  String toString() => 'EntityAccess not found: $accessId';
}
