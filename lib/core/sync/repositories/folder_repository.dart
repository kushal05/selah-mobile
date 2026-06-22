import 'package:drift/drift.dart';

import '../../database/sync_database.dart';
import '../models/folder_model.dart';
import '../models/oplog_entry.dart';
import 'base_sync_repository.dart';
import '../../testing/test_clock.dart';

/// Repository for folder operations
///
/// Per spec section 3.3:
/// - parent_id = NULL means root folder
/// - Folder name uniqueness enforced per parent
/// - Deleting a folder triggers recursive soft-delete
///
/// All write operations:
/// 1. Occur in a transaction
/// 2. Update updatedAt + version
/// 3. Create an oplog entry
class FolderRepository extends BaseSyncRepository<FolderModel> {
  final SyncDatabase _db;
  final String _deviceId;

  FolderRepository(this._db, this._deviceId);

  @override
  String get deviceId => _deviceId;

  @override
  OplogEntityType get entityType => OplogEntityType.folder;

  // ==================== READ OPERATIONS ====================

  /// Get all folders for a user (excluding deleted and trashed)
  /// Optionally filter by [type] ('note' or 'song')
  Future<List<FolderModel>> getAllFolders(String userId, {String? type}) async {
    final query = _db.select(_db.folders)
      ..where((f) {
        var condition = f.userId.equals(userId) & f.deleted.equals(0) & f.trashedAt.isNull();
        if (type != null) {
          condition = condition & f.type.equals(type);
        }
        return condition;
      })
      ..orderBy([(f) => OrderingTerm.asc(f.name)]);

    final rows = await query.get();
    return rows.map(_toModel).toList();
  }

  /// Get root folders for a user
  /// Optionally filter by [type] ('note' or 'song')
  Future<List<FolderModel>> getRootFolders(String userId, {String? type}) async {
    final query = _db.select(_db.folders)
      ..where((f) {
        var condition =
            f.userId.equals(userId) & f.parentId.isNull() & f.deleted.equals(0) & f.trashedAt.isNull();
        if (type != null) {
          condition = condition & f.type.equals(type);
        }
        return condition;
      })
      ..orderBy([(f) => OrderingTerm.asc(f.name)]);

    final rows = await query.get();
    return rows.map(_toModel).toList();
  }

  /// Get child folders of a parent
  Future<List<FolderModel>> getChildFolders(String parentId) async {
    final query = _db.select(_db.folders)
      ..where((f) => f.parentId.equals(parentId) & f.deleted.equals(0) & f.trashedAt.isNull())
      ..orderBy([(f) => OrderingTerm.asc(f.name)]);

    final rows = await query.get();
    return rows.map(_toModel).toList();
  }

  /// Get folder by ID
  Future<FolderModel?> getFolderById(String id) async {
    final query = _db.select(_db.folders)..where((f) => f.id.equals(id));

    final row = await query.getSingleOrNull();
    return row != null ? _toModel(row) : null;
  }

  /// Watch folder by ID (reactive stream)
  Stream<FolderModel?> watchFolderById(String id) {
    final query = _db.select(_db.folders)..where((f) => f.id.equals(id));

    return query.watchSingleOrNull().map((row) => row != null ? _toModel(row) : null);
  }

  /// Watch all folders for a user
  /// Optionally filter by [type] ('note' or 'song')
  Stream<List<FolderModel>> watchAllFolders(String userId, {String? type}) {
    final query = _db.select(_db.folders)
      ..where((f) {
        var condition = f.userId.equals(userId) & f.deleted.equals(0) & f.trashedAt.isNull();
        if (type != null) {
          condition = condition & f.type.equals(type);
        }
        return condition;
      })
      ..orderBy([(f) => OrderingTerm.asc(f.name)]);

    return query.watch().map((rows) => rows.map(_toModel).toList());
  }

  /// Get all soft-deleted folders for a user
  /// Optionally filter by [type] ('note' or 'song')
  Future<List<FolderModel>> getDeletedFolders(String userId, {String? type}) async {
    final query = _db.select(_db.folders)
      ..where((f) {
        var condition = f.userId.equals(userId) & f.deleted.equals(1);
        if (type != null) {
          condition = condition & f.type.equals(type);
        }
        return condition;
      })
      ..orderBy([(f) => OrderingTerm.desc(f.updatedAt)]);

    final rows = await query.get();
    return rows.map(_toModel).toList();
  }

  /// Restore a soft-deleted folder.
  /// If its parent is also deleted, restores to root.
  Future<FolderModel> restoreFolder(String id) async {
    final existing = await getFolderById(id);
    if (existing == null) {
      throw FolderNotFoundException(id);
    }

    // Check if parent still exists and is not deleted
    bool restoreToRoot = false;
    if (existing.parentId != null) {
      final parent = await getFolderById(existing.parentId!);
      if (parent == null || parent.isDeleted) {
        restoreToRoot = true;
      }
    }

    final restored = existing.restore(toRoot: restoreToRoot);

    await _db.transaction(() async {
      final oplogEntry = createUpdateOp(restored);

      await (_db.update(_db.folders)..where((f) => f.id.equals(id)))
          .write(_toCompanion(restored));

      await _db.into(_db.oplog).insert(_oplogToCompanion(oplogEntry));
    });

    return restored;
  }

  /// Check if folder name exists under parent (scoped by type)
  Future<bool> folderNameExists(
    String name,
    String? parentId,
    String userId, {
    String? excludeId,
    String? type,
  }) async {
    var query = _db.select(_db.folders)
      ..where((f) {
        var condition =
            f.name.equals(name) & f.userId.equals(userId) & f.deleted.equals(0) & f.trashedAt.isNull();
        if (type != null) {
          condition = condition & f.type.equals(type);
        }
        return condition;
      });

    if (parentId != null) {
      query = query..where((f) => f.parentId.equals(parentId));
    } else {
      query = query..where((f) => f.parentId.isNull());
    }

    if (excludeId != null) {
      query = query..where((f) => f.id.equals(excludeId).not());
    }

    final result = await query.getSingleOrNull();
    return result != null;
  }

  // ==================== WRITE OPERATIONS ====================

  /// Create a new folder
  ///
  /// Per spec: Transaction + oplog entry.
  /// When [parentId] is provided, visibility and groupId are inherited
  /// from the parent folder (ignoring any user-provided values).
  Future<FolderModel> createFolder({
    required String name,
    required String userId,
    String? parentId,
    String type = 'note',
    FolderVisibility visibility = FolderVisibility.personal,
    String? groupId,
  }) async {
    // Validate unique name under parent (scoped by type)
    if (await folderNameExists(name, parentId, userId, type: type)) {
      throw FolderNameConflictException(name, parentId);
    }

    // Inherit visibility from parent if creating a subfolder
    var effectiveVisibility = visibility;
    String? effectiveGroupId = groupId;
    if (parentId != null) {
      final parent = await getFolderById(parentId);
      if (parent != null) {
        effectiveVisibility = parent.visibility;
        effectiveGroupId = parent.groupId;
      }
    }

    final folder = FolderModel.create(
      id: generateId(),
      name: name,
      type: type,
      visibility: effectiveVisibility,
      groupId: effectiveGroupId,
      userId: userId,
      parentId: parentId,
    );

    final oplogEntry = createInsertOp(folder);

    await _db.transaction(() async {
      // Insert folder
      await _db.into(_db.folders).insert(_toCompanion(folder));

      // Insert oplog entry
      await _db.into(_db.oplog).insert(_oplogToCompanion(oplogEntry));
    });

    return folder;
  }

  /// Update a folder
  ///
  /// Per spec: Transaction + oplog entry + version increment.
  /// When [visibility] or [groupId] changes, all descendants are
  /// recursively updated to match (each with its own oplog entry).
  Future<FolderModel> updateFolder({
    required String id,
    String? name,
    String? parentId,
    bool clearParent = false,
    FolderVisibility? visibility,
    String? groupId,
    bool clearGroupId = false,
  }) async {
    final existing = await getFolderById(id);
    if (existing == null) {
      throw FolderNotFoundException(id);
    }

    // Validate unique name if changing
    if (name != null && name != existing.name) {
      final targetParent = clearParent ? null : (parentId ?? existing.parentId);
      if (await folderNameExists(name, targetParent, existing.userId,
          excludeId: id, type: existing.type)) {
        throw FolderNameConflictException(name, targetParent);
      }
    }

    // Prevent circular reference
    if (parentId != null) {
      if (parentId == id) {
        throw FolderCircularReferenceException(id, parentId);
      }
      // Check if new parent is a descendant
      if (await _isDescendant(parentId, id)) {
        throw FolderCircularReferenceException(id, parentId);
      }
    }

    final newVisibility = visibility ?? existing.visibility;
    final String? newGroupId;
    if (clearGroupId) {
      newGroupId = null;
    } else if (groupId != null) {
      newGroupId = groupId;
    } else if (newVisibility == FolderVisibility.group) {
      newGroupId = existing.groupId;
    } else {
      newGroupId = null;
    }

    final updated = FolderModel(
      id: existing.id,
      parentId: clearParent ? null : (parentId ?? existing.parentId),
      name: name ?? existing.name,
      type: existing.type,
      visibility: newVisibility,
      groupId: newGroupId,
      userId: existing.userId,
      updatedAt: TestClock.now(),
      version: existing.version + 1,
      deleted: existing.deleted,
      createdAt: existing.createdAt,
    );

    final oplogEntry = createUpdateOp(updated);

    // Check if visibility changed to cascade to descendants
    final visibilityChanged = newVisibility != existing.visibility ||
        newGroupId != existing.groupId;

    await _db.transaction(() async {
      await (_db.update(_db.folders)..where((f) => f.id.equals(id)))
          .write(_toCompanion(updated));

      await _db.into(_db.oplog).insert(_oplogToCompanion(oplogEntry));

      // Cascade visibility change to all descendants
      if (visibilityChanged) {
        final descendants = await getAllDescendants(id);
        for (final descendant in descendants) {
          final updatedDescendant = FolderModel(
            id: descendant.id,
            parentId: descendant.parentId,
            name: descendant.name,
            type: descendant.type,
            visibility: newVisibility,
            groupId: newGroupId,
            userId: descendant.userId,
            updatedAt: TestClock.now(),
            version: descendant.version + 1,
            deleted: descendant.deleted,
            createdAt: descendant.createdAt,
          );
          final descendantOplog = createUpdateOp(updatedDescendant);

          await (_db.update(_db.folders)
                ..where((f) => f.id.equals(descendant.id)))
              .write(_toCompanion(updatedDescendant));

          await _db
              .into(_db.oplog)
              .insert(_oplogToCompanion(descendantOplog));
        }
      }
    });

    return updated;
  }

  /// Soft delete a folder and all descendants
  ///
  /// Per spec section 3.3:
  /// - Sets deleted = 1
  /// - Triggers recursive soft-delete in app logic
  Future<void> deleteFolder(String id) async {
    final existing = await getFolderById(id);
    if (existing == null) {
      throw FolderNotFoundException(id);
    }

    // Get all descendant folders
    final descendants = await getAllDescendants(id);

    await _db.transaction(() async {
      // Soft delete the folder itself
      final deletedFolder = existing.softDelete();
      final oplogEntry = createDeleteOp(deletedFolder);

      await (_db.update(_db.folders)..where((f) => f.id.equals(id)))
          .write(_toCompanion(deletedFolder));

      await _db.into(_db.oplog).insert(_oplogToCompanion(oplogEntry));

      // Soft delete all descendants
      for (final descendant in descendants) {
        final deletedDescendant = descendant.softDelete();
        final descendantOplog = createDeleteOp(deletedDescendant);

        await (_db.update(_db.folders)..where((f) => f.id.equals(descendant.id)))
            .write(_toCompanion(deletedDescendant));

        await _db.into(_db.oplog).insert(_oplogToCompanion(descendantOplog));
      }
    });
  }

  // ==================== TRASH OPERATIONS ====================

  /// Move folder and all descendants to trash
  Future<void> trashFolder(String id) async {
    final existing = await getFolderById(id);
    if (existing == null) throw FolderNotFoundException(id);

    final descendants = await getAllDescendants(id);

    await _db.transaction(() async {
      final trashed = existing.moveToTrash();
      final oplogEntry = createUpdateOp(trashed);
      await (_db.update(_db.folders)..where((f) => f.id.equals(id)))
          .write(_toCompanion(trashed));
      await _db.into(_db.oplog).insert(_oplogToCompanion(oplogEntry));

      for (final descendant in descendants) {
        final trashedDesc = descendant.moveToTrash();
        final descOplog = createUpdateOp(trashedDesc);
        await (_db.update(_db.folders)..where((f) => f.id.equals(descendant.id)))
            .write(_toCompanion(trashedDesc));
        await _db.into(_db.oplog).insert(_oplogToCompanion(descOplog));
      }
    });
  }

  /// Restore folder from trash
  Future<FolderModel> restoreFromTrash(String id) async {
    final existing = await getFolderById(id);
    if (existing == null) throw FolderNotFoundException(id);

    final restored = existing.restoreFromTrash();
    final oplogEntry = createUpdateOp(restored);

    await _db.transaction(() async {
      await (_db.update(_db.folders)..where((f) => f.id.equals(id)))
          .write(_toCompanion(restored));
      await _db.into(_db.oplog).insert(_oplogToCompanion(oplogEntry));
    });

    return restored;
  }

  /// Get all trashed folders for a user
  Future<List<FolderModel>> getTrashedFolders(String userId) async {
    final query = _db.select(_db.folders)
      ..where((f) => f.userId.equals(userId) & f.deleted.equals(0) & f.trashedAt.isNotNull())
      ..orderBy([(f) => OrderingTerm.desc(f.trashedAt)]);
    final rows = await query.get();
    return rows.map(_toModel).toList();
  }

  /// Watch trashed folders for a user
  Stream<List<FolderModel>> watchTrashedFolders(String userId) {
    final query = _db.select(_db.folders)
      ..where((f) => f.userId.equals(userId) & f.deleted.equals(0) & f.trashedAt.isNotNull())
      ..orderBy([(f) => OrderingTerm.desc(f.trashedAt)]);
    return query.watch().map((rows) => rows.map(_toModel).toList());
  }

  // ==================== HELPER METHODS ====================

  /// Check if potentialDescendant is a descendant of ancestorId
  Future<bool> _isDescendant(String potentialDescendant, String ancestorId) async {
    var currentId = potentialDescendant;

    while (true) {
      final folder = await getFolderById(currentId);
      if (folder == null || folder.parentId == null) {
        return false;
      }
      if (folder.parentId == ancestorId) {
        return true;
      }
      currentId = folder.parentId!;
    }
  }

  /// Get all descendant folders (recursive)
  Future<List<FolderModel>> getAllDescendants(String folderId) async {
    final descendants = <FolderModel>[];
    final children = await getChildFolders(folderId);

    for (final child in children) {
      descendants.add(child);
      descendants.addAll(await getAllDescendants(child.id));
    }

    return descendants;
  }

  /// Convert database row to domain model
  FolderModel _toModel(Folder row) {
    return FolderModel(
      id: row.id,
      parentId: row.parentId,
      name: row.name,
      type: row.type,
      visibility: FolderVisibility.values.firstWhere(
        (v) => v.name == row.visibility,
        orElse: () => FolderVisibility.personal,
      ),
      groupId: row.groupId,
      userId: row.userId,
      updatedAt: row.updatedAt,
      version: row.version,
      deleted: row.deleted,
      trashedAt: row.trashedAt,
      createdAt: row.createdAt,
    );
  }

  /// Convert domain model to database companion
  FoldersCompanion _toCompanion(FolderModel model) {
    return FoldersCompanion(
      id: Value(model.id),
      parentId: Value(model.parentId),
      name: Value(model.name),
      type: Value(model.type),
      visibility: Value(model.visibility.name),
      groupId: Value(model.groupId),
      userId: Value(model.userId),
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

class FolderNotFoundException implements Exception {
  final String folderId;
  FolderNotFoundException(this.folderId);

  @override
  String toString() => 'Folder not found: $folderId';
}

class FolderNameConflictException implements Exception {
  final String name;
  final String? parentId;
  FolderNameConflictException(this.name, this.parentId);

  @override
  String toString() =>
      'Folder name "$name" already exists under parent: $parentId';
}

class FolderCircularReferenceException implements Exception {
  final String folderId;
  final String parentId;
  FolderCircularReferenceException(this.folderId, this.parentId);

  @override
  String toString() =>
      'Circular reference: Cannot set $parentId as parent of $folderId';
}

class RootFolderDeletionException implements Exception {
  final String folderId;
  RootFolderDeletionException(this.folderId);

  @override
  String toString() => 'Cannot delete root folder: $folderId';
}
