import 'package:flutter/material.dart';

import '../../testing/test_clock.dart';
import 'sync_entity.dart';

/// Visibility level for folders
enum FolderVisibility {
  personal, // Private to the user (default)
  group, // Shared with a specific group
  open; // Visible to everyone

  String get displayName => switch (this) {
        personal => 'Personal',
        group => 'Group',
        open => 'Open to All',
      };

  IconData get icon => switch (this) {
        personal => Icons.lock_rounded,
        group => Icons.group_rounded,
        open => Icons.public_rounded,
      };
}

/// Domain model for Folder
///
/// Per spec section 3.3:
/// - parent_id = NULL means root folder
/// - Folder name uniqueness enforced per parent
/// - Deleting sets deleted = 1 and triggers recursive soft-delete
class FolderModel implements SyncEntity {
  @override
  final String id;

  /// Parent folder ID (null for root folders)
  final String? parentId;

  /// Folder name
  final String name;

  /// Folder type: 'note' or 'song'
  final String type;

  /// Visibility level
  final FolderVisibility visibility;

  /// Group ID (only set when visibility = group)
  final String? groupId;

  /// Owner user ID
  final String userId;

  @override
  final int updatedAt;

  @override
  final int version;

  /// Soft delete flag
  final int deleted;

  @override
  final int? trashedAt;

  /// Creation timestamp
  final int createdAt;

  const FolderModel({
    required this.id,
    this.parentId,
    required this.name,
    this.type = 'note',
    this.visibility = FolderVisibility.personal,
    this.groupId,
    required this.userId,
    required this.updatedAt,
    required this.version,
    required this.deleted,
    this.trashedAt,
    required this.createdAt,
  });

  @override
  bool get isDeleted => deleted == 1;

  /// Check if this is a root folder
  bool get isRoot => parentId == null;

  @override
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'parentId': parentId,
      'name': name,
      'type': type,
      'visibility': visibility.name,
      'groupId': groupId,
      'userId': userId,
      'updatedAt': updatedAt,
      'version': version,
      'deleted': deleted,
      if (trashedAt != null) 'trashedAt': trashedAt,
      'createdAt': createdAt,
    };
  }

  factory FolderModel.fromJson(Map<String, dynamic> json) {
    return FolderModel(
      id: (json['id'] ?? json['_id']) as String,
      parentId: json['parentId'] as String?,
      name: json['name'] as String,
      type: json['type'] as String? ?? 'note',
      visibility: FolderVisibility.values.firstWhere(
        (v) => v.name == json['visibility'],
        orElse: () => FolderVisibility.personal,
      ),
      groupId: json['groupId'] as String?,
      userId: json['userId'] as String,
      updatedAt: json['updatedAt'] as int,
      version: json['version'] as int,
      deleted: _parseDeleted(json['deleted']),
      trashedAt: json['trashedAt'] as int?,
      createdAt: json['createdAt'] as int,
    );
  }

  /// Create a new folder
  factory FolderModel.create({
    required String id,
    String? parentId,
    required String name,
    String type = 'note',
    FolderVisibility visibility = FolderVisibility.personal,
    String? groupId,
    required String userId,
  }) {
    final now = TestClock.now();
    return FolderModel(
      id: id,
      parentId: parentId,
      name: name,
      type: type,
      visibility: visibility,
      groupId: groupId,
      userId: userId,
      updatedAt: now,
      version: 1,
      deleted: 0,
      createdAt: now,
    );
  }

  /// Create updated copy with incremented version
  FolderModel copyWithUpdate({
    String? parentId,
    String? name,
    FolderVisibility? visibility,
    String? groupId,
    bool clearGroupId = false,
  }) {
    return FolderModel(
      id: id,
      parentId: parentId ?? this.parentId,
      name: name ?? this.name,
      type: type,
      visibility: visibility ?? this.visibility,
      groupId: clearGroupId ? null : (groupId ?? this.groupId),
      userId: userId,
      updatedAt: TestClock.now(),
      version: version + 1,
      deleted: deleted,
      trashedAt: trashedAt,
      createdAt: createdAt,
    );
  }

  /// Create soft-deleted copy
  FolderModel softDelete() {
    return FolderModel(
      id: id,
      parentId: parentId,
      name: name,
      type: type,
      visibility: visibility,
      groupId: groupId,
      userId: userId,
      updatedAt: TestClock.now(),
      version: version + 1,
      deleted: 1,
      trashedAt: trashedAt,
      createdAt: createdAt,
    );
  }

  /// Move to trash (recoverable)
  FolderModel moveToTrash() {
    final now = TestClock.now();
    return FolderModel(
      id: id,
      parentId: parentId,
      name: name,
      type: type,
      visibility: visibility,
      groupId: groupId,
      userId: userId,
      updatedAt: now,
      version: version + 1,
      deleted: deleted,
      trashedAt: now,
      createdAt: createdAt,
    );
  }

  /// Restore from trash
  FolderModel restoreFromTrash() {
    return FolderModel(
      id: id,
      parentId: parentId,
      name: name,
      type: type,
      visibility: visibility,
      groupId: groupId,
      userId: userId,
      updatedAt: TestClock.now(),
      version: version + 1,
      deleted: deleted,
      trashedAt: null,
      createdAt: createdAt,
    );
  }

  /// Restore a soft-deleted folder.
  /// If [toRoot] is true, clears parentId (useful when parent is also deleted).
  FolderModel restore({bool toRoot = false}) {
    return FolderModel(
      id: id,
      parentId: toRoot ? null : parentId,
      name: name,
      type: type,
      visibility: visibility,
      groupId: groupId,
      userId: userId,
      updatedAt: TestClock.now(),
      version: version + 1,
      deleted: 0,
      trashedAt: trashedAt,
      createdAt: createdAt,
    );
  }

  /// Parses deleted flag that may be bool (from API) or int (from local DB).
  static int _parseDeleted(dynamic value) {
    if (value is bool) return value ? 1 : 0;
    if (value is int) return value;
    return 0;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FolderModel &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          version == other.version;

  @override
  int get hashCode => id.hashCode ^ version.hashCode;

  @override
  String toString() {
    return 'FolderModel(id: $id, name: $name, type: $type, visibility: ${visibility.name}, v$version, deleted: $isDeleted)';
  }
}
