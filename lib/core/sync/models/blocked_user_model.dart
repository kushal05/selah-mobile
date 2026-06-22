import 'sync_entity.dart';
import '../../testing/test_clock.dart';

/// Domain model for BlockedUser
///
/// Represents a user blocked by the current user
class BlockedUserModel implements SyncEntity {
  @override
  final String id;

  /// Owner user ID (who blocked)
  final String userId;

  /// Blocked user's ID
  final String blockedUserId;

  /// Blocked user's username (denormalized)
  final String blockedUsername;

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

  const BlockedUserModel({
    required this.id,
    required this.userId,
    required this.blockedUserId,
    required this.blockedUsername,
    required this.updatedAt,
    required this.version,
    required this.deleted,
    this.trashedAt,
    required this.createdAt,
  });

  @override
  bool get isDeleted => deleted == 1;

  @override
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userId': userId,
      'blockedUserId': blockedUserId,
      'blockedUsername': blockedUsername,
      'updatedAt': updatedAt,
      'version': version,
      'deleted': deleted,
      if (trashedAt != null) 'trashedAt': trashedAt,
      'createdAt': createdAt,
    };
  }

  factory BlockedUserModel.fromJson(Map<String, dynamic> json) {
    return BlockedUserModel(
      id: (json['id'] ?? json['_id']) as String,
      userId: json['userId'] as String,
      blockedUserId: json['blockedUserId'] as String,
      blockedUsername: json['blockedUsername'] as String,
      updatedAt: json['updatedAt'] as int,
      version: json['version'] as int,
      deleted: _parseDeleted(json['deleted']),
      trashedAt: json['trashedAt'] as int?,
      createdAt: json['createdAt'] as int,
    );
  }

  factory BlockedUserModel.create({
    required String id,
    required String userId,
    required String blockedUserId,
    required String blockedUsername,
  }) {
    final now = TestClock.now();
    return BlockedUserModel(
      id: id,
      userId: userId,
      blockedUserId: blockedUserId,
      blockedUsername: blockedUsername,
      updatedAt: now,
      version: 1,
      deleted: 0,
      createdAt: now,
    );
  }

  BlockedUserModel softDelete() {
    return BlockedUserModel(
      id: id,
      userId: userId,
      blockedUserId: blockedUserId,
      blockedUsername: blockedUsername,
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
      other is BlockedUserModel &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          version == other.version;

  @override
  int get hashCode => id.hashCode ^ version.hashCode;

  @override
  String toString() =>
      'BlockedUserModel(id: $id, blocked: $blockedUsername, v$version)';
}
