import '../../domain/enums/group_enums.dart';
import 'sync_entity.dart';
import '../../testing/test_clock.dart';

/// Domain model for GroupMember
///
/// Represents a user's membership in a group
class GroupMemberModel implements SyncEntity {
  @override
  final String id;

  /// Group ID
  final String groupId;

  /// Member's user ID
  final String memberUserId;

  /// Member's username (denormalized)
  final String memberUsername;

  /// Member's display name (denormalized)
  final String memberDisplayName;

  /// Member's role in the group
  final GroupMemberRole role;

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

  const GroupMemberModel({
    required this.id,
    required this.groupId,
    required this.memberUserId,
    required this.memberUsername,
    required this.memberDisplayName,
    required this.role,
    required this.userId,
    required this.updatedAt,
    required this.version,
    required this.deleted,
    this.trashedAt,
    required this.createdAt,
  });

  @override
  bool get isDeleted => deleted == 1;

  /// Get display name for the member
  String get displayName =>
      memberDisplayName.isNotEmpty ? memberDisplayName : memberUsername;

  /// Get initials for avatar
  String get initials {
    final name = displayName;
    final parts = name.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  /// Whether this member is an admin
  bool get isAdmin => role == GroupMemberRole.admin;

  /// Whether this member can manage (admin or moderator)
  bool get canManage =>
      role == GroupMemberRole.admin || role == GroupMemberRole.moderator;

  @override
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'groupId': groupId,
      'memberUserId': memberUserId,
      'memberUsername': memberUsername,
      'memberDisplayName': memberDisplayName,
      'role': role.name,
      'userId': userId,
      'updatedAt': updatedAt,
      'version': version,
      'deleted': deleted,
      if (trashedAt != null) 'trashedAt': trashedAt,
      'createdAt': createdAt,
    };
  }

  factory GroupMemberModel.fromJson(Map<String, dynamic> json) {
    return GroupMemberModel(
      id: (json['id'] ?? json['_id']) as String,
      groupId: json['groupId'] as String,
      memberUserId: json['memberUserId'] as String,
      memberUsername: json['memberUsername'] as String? ?? '',
      memberDisplayName: json['memberDisplayName'] as String? ?? '',
      role: GroupMemberRole.values.firstWhere(
        (r) => r.name == json['role'],
        orElse: () => GroupMemberRole.member,
      ),
      userId: json['userId'] as String,
      updatedAt: json['updatedAt'] as int,
      version: json['version'] as int,
      deleted: _parseDeleted(json['deleted']),
      trashedAt: json['trashedAt'] as int?,
      createdAt: json['createdAt'] as int,
    );
  }

  factory GroupMemberModel.create({
    required String id,
    required String groupId,
    required String memberUserId,
    required String memberUsername,
    String memberDisplayName = '',
    required String userId,
    GroupMemberRole role = GroupMemberRole.member,
  }) {
    final now = TestClock.now();
    return GroupMemberModel(
      id: id,
      groupId: groupId,
      memberUserId: memberUserId,
      memberUsername: memberUsername,
      memberDisplayName: memberDisplayName,
      role: role,
      userId: userId,
      updatedAt: now,
      version: 1,
      deleted: 0,
      createdAt: now,
    );
  }

  GroupMemberModel copyWithRole(GroupMemberRole newRole) {
    return GroupMemberModel(
      id: id,
      groupId: groupId,
      memberUserId: memberUserId,
      memberUsername: memberUsername,
      memberDisplayName: memberDisplayName,
      role: newRole,
      userId: userId,
      updatedAt: TestClock.now(),
      version: version + 1,
      deleted: deleted,
      trashedAt: trashedAt,
      createdAt: createdAt,
    );
  }

  GroupMemberModel softDelete() {
    return GroupMemberModel(
      id: id,
      groupId: groupId,
      memberUserId: memberUserId,
      memberUsername: memberUsername,
      memberDisplayName: memberDisplayName,
      role: role,
      userId: userId,
      updatedAt: TestClock.now(),
      version: version + 1,
      deleted: 1,
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
      other is GroupMemberModel &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          version == other.version;

  @override
  int get hashCode => id.hashCode ^ version.hashCode;

  @override
  String toString() =>
      'GroupMemberModel(id: $id, user: $memberUsername, '
      'role: ${role.name}, v$version)';
}
