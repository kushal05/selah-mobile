import 'sync_entity.dart';
import '../../testing/test_clock.dart';

/// Access type for entity_access records
enum AccessType {
  owner,
  user,
  friend,
  group,
  public_;

  String toDbValue() {
    switch (this) {
      case AccessType.owner:
        return 'owner';
      case AccessType.user:
        return 'user';
      case AccessType.friend:
        return 'friend';
      case AccessType.group:
        return 'group';
      case AccessType.public_:
        return 'public';
    }
  }

  static AccessType fromDbValue(String value) {
    switch (value) {
      case 'owner':
        return AccessType.owner;
      case 'user':
        return AccessType.user;
      case 'friend':
        return AccessType.friend;
      case 'group':
        return AccessType.group;
      case 'public':
        return AccessType.public_;
      default:
        // Default to owner for unknown values to avoid crash during sync
        return AccessType.owner;
    }
  }
}

/// Role for entity_access records
enum AccessRole {
  viewer,
  editor,
  admin,
  owner;

  String toDbValue() {
    switch (this) {
      case AccessRole.viewer:
        return 'viewer';
      case AccessRole.editor:
        return 'editor';
      case AccessRole.admin:
        return 'admin';
      case AccessRole.owner:
        return 'owner';
    }
  }

  static AccessRole fromDbValue(String value) {
    switch (value) {
      case 'viewer':
        return AccessRole.viewer;
      case 'editor':
        return AccessRole.editor;
      case 'admin':
        return AccessRole.admin;
      case 'owner':
        return AccessRole.owner;
      default:
        return AccessRole.viewer;
    }
  }

  /// Whether this role can edit content
  bool get canEdit => this == AccessRole.editor || this == AccessRole.admin || this == AccessRole.owner;

  /// Whether this role can manage access (share/unshare)
  bool get canManage => this == AccessRole.admin || this == AccessRole.owner;
}

/// Domain model for universal entity access control.
///
/// Controls visibility for any content entity (note, song, prayer, promise, folder).
/// Replaces ad-hoc sharing (SharedPrayers, PrayerCollaborators, folder.visibility).
class EntityAccessModel implements SyncEntity {
  @override
  final String id;

  /// Type of entity: note, song, prayer, promise, folder
  final String entityType;

  /// ID of the entity being shared
  final String entityId;

  /// Access grant type
  final AccessType accessType;

  /// Target of the grant (userId for 'user', groupId for 'group', null otherwise)
  final String? targetId;

  /// Permission level
  final AccessRole role;

  /// Owner user ID — sync partition key
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

  /// Acceptance timestamp — NULL for pending tier-2 user shares,
  /// set (equal to createdAt) for owner/friend/group/public grants.
  final int? acceptedAt;

  const EntityAccessModel({
    required this.id,
    required this.entityType,
    required this.entityId,
    required this.accessType,
    this.targetId,
    this.role = AccessRole.viewer,
    required this.userId,
    required this.updatedAt,
    required this.version,
    required this.deleted,
    this.trashedAt,
    required this.createdAt,
    this.acceptedAt,
  });

  /// True when the grant is active for permission checks.
  /// Tier-2 user shares require explicit accept; others are auto-accepted.
  bool get isAccepted => acceptedAt != null;

  @override
  bool get isDeleted => deleted == 1;

  @override
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'entityType': entityType,
      'entityId': entityId,
      'accessType': accessType.toDbValue(),
      'targetId': targetId,
      'role': role.toDbValue(),
      'userId': userId,
      'updatedAt': updatedAt,
      'version': version,
      'deleted': deleted,
      if (trashedAt != null) 'trashedAt': trashedAt,
      'createdAt': createdAt,
      if (acceptedAt != null) 'acceptedAt': acceptedAt,
    };
  }

  factory EntityAccessModel.fromJson(Map<String, dynamic> json) {
    return EntityAccessModel(
      id: (json['id'] ?? json['_id']) as String,
      entityType: json['entityType'] as String,
      entityId: json['entityId'] as String,
      accessType: AccessType.fromDbValue(json['accessType'] as String),
      targetId: json['targetId'] as String?,
      role: AccessRole.fromDbValue(json['role'] as String? ?? 'viewer'),
      userId: json['userId'] as String,
      updatedAt: json['updatedAt'] as int,
      version: json['version'] as int,
      deleted: _parseDeleted(json['deleted']),
      trashedAt: json['trashedAt'] as int?,
      createdAt: json['createdAt'] as int,
      acceptedAt: json['acceptedAt'] as int?,
    );
  }

  /// Create a new entity_access record.
  ///
  /// Tier-2 `user` grants default to pending (acceptedAt = null) — the
  /// recipient must explicitly accept from their inbox before the gate
  /// activates. All other access types are implicitly accepted at creation.
  factory EntityAccessModel.create({
    required String id,
    required String entityType,
    required String entityId,
    required AccessType accessType,
    String? targetId,
    AccessRole role = AccessRole.viewer,
    required String userId,
  }) {
    final now = TestClock.now();
    final implicitAccept = accessType != AccessType.user;
    return EntityAccessModel(
      id: id,
      entityType: entityType,
      entityId: entityId,
      accessType: accessType,
      targetId: targetId,
      role: role,
      userId: userId,
      updatedAt: now,
      version: 1,
      deleted: 0,
      createdAt: now,
      acceptedAt: implicitAccept ? now : null,
    );
  }

  /// Create an owner access record for an entity.
  factory EntityAccessModel.ownerAccess({
    required String id,
    required String entityType,
    required String entityId,
    required String userId,
  }) {
    final now = TestClock.now();
    return EntityAccessModel(
      id: id,
      entityType: entityType,
      entityId: entityId,
      accessType: AccessType.owner,
      targetId: null,
      role: AccessRole.owner,
      userId: userId,
      updatedAt: now,
      version: 1,
      deleted: 0,
      createdAt: now,
      acceptedAt: now,
    );
  }

  /// Mark a pending tier-2 user share as accepted.
  /// Bumps version so the oplog entry reflects the state change.
  EntityAccessModel accept() {
    if (acceptedAt != null) return this;
    final now = TestClock.now();
    return EntityAccessModel(
      id: id,
      entityType: entityType,
      entityId: entityId,
      accessType: accessType,
      targetId: targetId,
      role: role,
      userId: userId,
      updatedAt: now,
      version: version + 1,
      deleted: deleted,
      trashedAt: trashedAt,
      createdAt: createdAt,
      acceptedAt: now,
    );
  }

  EntityAccessModel copyWithUpdate({
    AccessRole? role,
  }) {
    final now = TestClock.now();
    return EntityAccessModel(
      id: id,
      entityType: entityType,
      entityId: entityId,
      accessType: accessType,
      targetId: targetId,
      role: role ?? this.role,
      userId: userId,
      updatedAt: now,
      version: version + 1,
      deleted: deleted,
      trashedAt: trashedAt,
      createdAt: createdAt,
      acceptedAt: acceptedAt,
    );
  }

  EntityAccessModel softDelete() {
    return EntityAccessModel(
      id: id,
      entityType: entityType,
      entityId: entityId,
      accessType: accessType,
      targetId: targetId,
      role: role,
      userId: userId,
      updatedAt: TestClock.now(),
      version: version + 1,
      deleted: 1,
      trashedAt: trashedAt,
      createdAt: createdAt,
      acceptedAt: acceptedAt,
    );
  }

  static int _parseDeleted(dynamic value) {
    if (value is bool) return value ? 1 : 0;
    if (value is int) return value;
    return 0;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EntityAccessModel &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          version == other.version;

  @override
  int get hashCode => id.hashCode ^ version.hashCode;

  @override
  String toString() =>
      'EntityAccessModel(id: $id, entity: $entityType/$entityId, '
      'access: ${accessType.toDbValue()}, role: ${role.toDbValue()}, v$version)';
}
