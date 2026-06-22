import 'dart:convert';

import 'package:drift/drift.dart';

import '../../database/sync_database.dart';
import '../../database/tables/groups_table.dart';
import '../models/group_model.dart';
import '../models/oplog_entry.dart';
import 'base_sync_repository.dart';

/// Repository for group operations with oplog-based sync.
class GroupRepository extends BaseSyncRepository<GroupModel> {
  final SyncDatabase _db;
  final String _deviceId;

  GroupRepository(this._db, this._deviceId);

  @override
  String get deviceId => _deviceId;

  @override
  OplogEntityType get entityType => OplogEntityType.group;

  // ==================== READ OPERATIONS ====================

  Future<GroupModel?> getGroupById(String id) async {
    final row = await (_db.select(_db.groups)
          ..where((g) => g.id.equals(id)))
        .getSingleOrNull();
    return row != null ? _toModel(row) : null;
  }

  Future<List<GroupModel>> getAllGroups(String userId) async {
    final query = _db.select(_db.groups)
      ..where((g) => g.deleted.equals(0) & g.userId.equals(userId))
      ..orderBy([(g) => OrderingTerm.desc(g.updatedAt)]);
    final rows = await query.get();
    return rows.map(_toModel).toList();
  }

  Stream<List<GroupModel>> watchAllGroups(String userId) {
    final query = _db.select(_db.groups)
      ..where((g) => g.deleted.equals(0) & g.userId.equals(userId))
      ..orderBy([(g) => OrderingTerm.desc(g.updatedAt)]);
    return query.watch().map((rows) => rows.map(_toModel).toList());
  }

  // ==================== WRITE OPERATIONS ====================

  Future<GroupModel> createGroup({
    required String name,
    String description = '',
    GroupType groupType = GroupType.church,
    String? imageUrl,
    GroupJoinPolicy joinPolicy = GroupJoinPolicy.codeOnly,
    required String createdByUserId,
    required String userId,
  }) async {
    final group = GroupModel.create(
      id: generateId(),
      name: name,
      description: description,
      groupType: groupType,
      imageUrl: imageUrl,
      joinPolicy: joinPolicy,
      createdByUserId: createdByUserId,
      userId: userId,
    );

    final oplogEntry = createInsertOp(group);

    await _db.transaction(() async {
      await _db.into(_db.groups).insert(_toCompanion(group));
      await _db.into(_db.oplog).insert(_oplogToCompanion(oplogEntry));
    });

    return group;
  }

  Future<GroupModel> updateGroup({
    required String id,
    String? name,
    String? description,
    GroupType? groupType,
    String? imageUrl,
    bool clearImageUrl = false,
    GroupJoinPolicy? joinPolicy,
  }) async {
    final existing = await getGroupById(id);
    if (existing == null) {
      throw GroupNotFoundException(id);
    }

    final updated = existing.copyWithUpdate(
      name: name,
      description: description,
      groupType: groupType,
      imageUrl: imageUrl,
      clearImageUrl: clearImageUrl,
      joinPolicy: joinPolicy,
    );

    final oplogEntry = createUpdateOp(updated);

    await _db.transaction(() async {
      await (_db.update(_db.groups)..where((g) => g.id.equals(id)))
          .write(_toCompanion(updated));
      await _db.into(_db.oplog).insert(_oplogToCompanion(oplogEntry));
    });

    return updated;
  }

  Future<void> deleteGroup(String id) async {
    final existing = await getGroupById(id);
    if (existing == null) {
      throw GroupNotFoundException(id);
    }

    final deleted = existing.softDelete();
    final oplogEntry = createDeleteOp(deleted);

    await _db.transaction(() async {
      await (_db.update(_db.groups)..where((g) => g.id.equals(id)))
          .write(_toCompanion(deleted));
      await _db.into(_db.oplog).insert(_oplogToCompanion(oplogEntry));
    });
  }

  // ==================== HELPER METHODS ====================

  GroupModel _toModel(Group row) {
    return GroupModel(
      id: row.id,
      name: row.name,
      description: row.description,
      groupType: GroupType.values.firstWhere(
        (t) => t.name == row.groupType,
        orElse: () => GroupType.church,
      ),
      imageUrl: row.imageUrl,
      joinCode: row.joinCode,
      joinPolicy: GroupJoinPolicy.values.firstWhere(
        (p) => p.name == row.joinPolicy,
        orElse: () => GroupJoinPolicy.codeOnly,
      ),
      createdByUserId: row.createdByUserId,
      userId: row.userId,
      updatedAt: row.updatedAt,
      version: row.version,
      deleted: row.deleted,
      createdAt: row.createdAt,
      fieldUpdatedAt: _parseFieldTimestamps(row.fieldUpdatedAt),
    );
  }

  GroupsCompanion _toCompanion(GroupModel model) {
    return GroupsCompanion(
      id: Value(model.id),
      name: Value(model.name),
      description: Value(model.description),
      groupType: Value(model.groupType.name),
      imageUrl: Value(model.imageUrl),
      joinCode: Value(model.joinCode),
      joinPolicy: Value(model.joinPolicy.name),
      createdByUserId: Value(model.createdByUserId),
      userId: Value(model.userId),
      updatedAt: Value(model.updatedAt),
      version: Value(model.version),
      deleted: Value(model.deleted),
      createdAt: Value(model.createdAt),
      fieldUpdatedAt: Value(jsonEncode(model.fieldUpdatedAt)),
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

  static Map<String, int> _parseFieldTimestamps(String raw) {
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map((k, v) => MapEntry(k, (v as num).toInt()));
    } catch (_) {
      return {};
    }
  }
}

class GroupNotFoundException implements Exception {
  final String groupId;
  GroupNotFoundException(this.groupId);

  @override
  String toString() => 'Group not found: $groupId';
}
