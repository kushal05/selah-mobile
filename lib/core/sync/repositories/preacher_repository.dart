import 'package:drift/drift.dart';

import '../../database/sync_database.dart';
import '../models/oplog_entry.dart';
import '../models/preacher_model.dart';
import 'base_sync_repository.dart';

/// Repository for preacher operations (sync-enabled)
class PreacherRepository extends BaseSyncRepository<PreacherModel> {
  final SyncDatabase _db;
  final String _deviceId;

  PreacherRepository(this._db, this._deviceId);

  @override
  String get deviceId => _deviceId;

  @override
  OplogEntityType get entityType => OplogEntityType.preacher;

  // ==================== READ OPERATIONS ====================

  Future<List<PreacherModel>> getAllPreachers(String userId) async {
    final query = _db.select(_db.syncPreachers)
      ..where((p) => p.userId.equals(userId) & p.deleted.equals(0) & p.trashedAt.isNull())
      ..orderBy([(p) => OrderingTerm.asc(p.name)]);

    final rows = await query.get();
    return rows.map(_toModel).toList();
  }

  Future<PreacherModel?> getPreacherById(String id) async {
    final query = _db.select(_db.syncPreachers)
      ..where((p) => p.id.equals(id));

    final row = await query.getSingleOrNull();
    return row != null ? _toModel(row) : null;
  }

  Future<PreacherModel?> getPreacherByName(String name, String userId) async {
    final query = _db.select(_db.syncPreachers)
      ..where(
          (p) => p.name.equals(name) & p.userId.equals(userId) & p.deleted.equals(0) & p.trashedAt.isNull());

    final row = await query.getSingleOrNull();
    return row != null ? _toModel(row) : null;
  }

  Stream<List<PreacherModel>> watchAllPreachers(String userId) {
    final query = _db.select(_db.syncPreachers)
      ..where((p) => p.userId.equals(userId) & p.deleted.equals(0) & p.trashedAt.isNull())
      ..orderBy([(p) => OrderingTerm.asc(p.name)]);

    return query.watch().map((rows) => rows.map(_toModel).toList());
  }

  // ==================== WRITE OPERATIONS ====================

  Future<PreacherModel> createPreacher({
    required String userId,
    required String name,
  }) async {
    final preacher = PreacherModel.create(
      id: generateId(),
      userId: userId,
      name: name,
    );

    final oplogEntry = createInsertOp(preacher);

    await _db.transaction(() async {
      await _db.into(_db.syncPreachers).insert(_toCompanion(preacher));
      await _db.into(_db.oplog).insert(_oplogToCompanion(oplogEntry));
    });

    return preacher;
  }

  /// Get an existing preacher by name, or create a new one.
  Future<PreacherModel> getOrCreatePreacher(String name, String userId) async {
    final existing = await getPreacherByName(name, userId);
    if (existing != null) return existing;
    return createPreacher(userId: userId, name: name);
  }

  /// Move a preacher to the trash
  Future<PreacherModel> trashPreacher(String id) async {
    final existing = await getPreacherById(id);
    if (existing == null) throw PreacherNotFoundException(id);
    final trashed = existing.moveToTrash();
    final oplogEntry = createUpdateOp(trashed);
    await _db.transaction(() async {
      await (_db.update(_db.syncPreachers)..where((p) => p.id.equals(id)))
          .write(_toCompanion(trashed));
      await _db.into(_db.oplog).insert(_oplogToCompanion(oplogEntry));
    });
    return trashed;
  }

  /// Restore a preacher from the trash
  Future<PreacherModel> restorePreacher(String id) async {
    final existing = await getPreacherById(id);
    if (existing == null) throw PreacherNotFoundException(id);
    final restored = existing.restoreFromTrash();
    final oplogEntry = createUpdateOp(restored);
    await _db.transaction(() async {
      await (_db.update(_db.syncPreachers)..where((p) => p.id.equals(id)))
          .write(_toCompanion(restored));
      await _db.into(_db.oplog).insert(_oplogToCompanion(oplogEntry));
    });
    return restored;
  }

  /// Get all trashed preachers for a user
  Future<List<PreacherModel>> getTrashedPreachers(String userId) async {
    final query = _db.select(_db.syncPreachers)
      ..where((p) => p.userId.equals(userId) & p.deleted.equals(0) & p.trashedAt.isNotNull())
      ..orderBy([(p) => OrderingTerm.desc(p.trashedAt)]);
    final rows = await query.get();
    return rows.map(_toModel).toList();
  }

  /// Watch all trashed preachers for a user
  Stream<List<PreacherModel>> watchTrashedPreachers(String userId) {
    final query = _db.select(_db.syncPreachers)
      ..where((p) => p.userId.equals(userId) & p.deleted.equals(0) & p.trashedAt.isNotNull())
      ..orderBy([(p) => OrderingTerm.desc(p.trashedAt)]);
    return query.watch().map((rows) => rows.map(_toModel).toList());
  }

  Future<void> deletePreacher(String id) async {
    final existing = await getPreacherById(id);
    if (existing == null) return;

    final deleted = existing.softDelete();
    final oplogEntry = createDeleteOp(deleted);

    await _db.transaction(() async {
      await (_db.update(_db.syncPreachers)..where((p) => p.id.equals(id)))
          .write(_toCompanion(deleted));
      await _db.into(_db.oplog).insert(_oplogToCompanion(oplogEntry));
    });
  }

  // ==================== HELPERS ====================

  PreacherModel _toModel(SyncPreacher row) {
    return PreacherModel(
      id: row.id,
      userId: row.userId,
      name: row.name,
      updatedAt: row.updatedAt,
      version: row.version,
      deleted: row.deleted,
      trashedAt: row.trashedAt,
      createdAt: row.createdAt,
    );
  }

  SyncPreachersCompanion _toCompanion(PreacherModel model) {
    return SyncPreachersCompanion(
      id: Value(model.id),
      userId: Value(model.userId),
      name: Value(model.name),
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

class PreacherNotFoundException implements Exception {
  final String preacherId;
  PreacherNotFoundException(this.preacherId);

  @override
  String toString() => 'Preacher not found: $preacherId';
}
