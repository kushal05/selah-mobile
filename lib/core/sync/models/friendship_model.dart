import 'sync_entity.dart';
import '../../testing/test_clock.dart';

/// Domain model for Friendship
///
/// Represents an active friendship between two users
class FriendshipModel implements SyncEntity {
  @override
  final String id;

  /// Owner user ID
  final String userId;

  /// Friend's user ID
  final String friendUserId;

  /// Friend's username (denormalized)
  final String friendUsername;

  /// Friend's display name (denormalized)
  final String friendDisplayName;

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

  const FriendshipModel({
    required this.id,
    required this.userId,
    required this.friendUserId,
    required this.friendUsername,
    required this.friendDisplayName,
    required this.updatedAt,
    required this.version,
    required this.deleted,
    this.trashedAt,
    required this.createdAt,
  });

  @override
  bool get isDeleted => deleted == 1;

  /// Get initials for avatar display
  String get initials {
    final name =
        friendDisplayName.isNotEmpty ? friendDisplayName : friendUsername;
    if (name.isEmpty) return '?';
    final parts = name.trim().split(' ');
    if (parts.length == 1) {
      return parts[0][0].toUpperCase();
    }
    return '${parts[0][0]}${parts.last[0]}'.toUpperCase();
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userId': userId,
      'friendUserId': friendUserId,
      'friendUsername': friendUsername,
      'friendDisplayName': friendDisplayName,
      'updatedAt': updatedAt,
      'version': version,
      'deleted': deleted,
      if (trashedAt != null) 'trashedAt': trashedAt,
      'createdAt': createdAt,
    };
  }

  factory FriendshipModel.fromJson(Map<String, dynamic> json) {
    return FriendshipModel(
      id: (json['id'] ?? json['_id']) as String,
      userId: json['userId'] as String,
      friendUserId: json['friendUserId'] as String,
      friendUsername: json['friendUsername'] as String,
      friendDisplayName: json['friendDisplayName'] as String? ?? '',
      updatedAt: json['updatedAt'] as int,
      version: json['version'] as int,
      deleted: _parseDeleted(json['deleted']),
      trashedAt: json['trashedAt'] as int?,
      createdAt: json['createdAt'] as int,
    );
  }

  factory FriendshipModel.create({
    required String id,
    required String userId,
    required String friendUserId,
    required String friendUsername,
    String friendDisplayName = '',
  }) {
    final now = TestClock.now();
    return FriendshipModel(
      id: id,
      userId: userId,
      friendUserId: friendUserId,
      friendUsername: friendUsername,
      friendDisplayName: friendDisplayName,
      updatedAt: now,
      version: 1,
      deleted: 0,
      createdAt: now,
    );
  }

  FriendshipModel softDelete() {
    return FriendshipModel(
      id: id,
      userId: userId,
      friendUserId: friendUserId,
      friendUsername: friendUsername,
      friendDisplayName: friendDisplayName,
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
      other is FriendshipModel &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          version == other.version;

  @override
  int get hashCode => id.hashCode ^ version.hashCode;

  @override
  String toString() =>
      'FriendshipModel(id: $id, friend: $friendUsername, v$version)';
}
