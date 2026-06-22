import '../../domain/enums/friend_enums.dart';
import 'sync_entity.dart';
import '../../testing/test_clock.dart';

/// Domain model for FriendRequest
///
/// Represents a pending, accepted, or rejected friend request
class FriendRequestModel implements SyncEntity {
  @override
  final String id;

  /// Owner user ID
  final String userId;

  /// Sender user ID
  final String fromUserId;

  /// Sender username (denormalized)
  final String fromUsername;

  /// Sender display name (denormalized)
  final String fromDisplayName;

  /// Recipient user ID
  final String toUserId;

  /// Recipient username (denormalized)
  final String toUsername;

  /// Recipient display name (denormalized)
  final String toDisplayName;

  /// Request status
  final FriendRequestStatus status;

  /// Deterministic key for the user pair (sorted user IDs joined by _)
  final String? userPairKey;

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

  const FriendRequestModel({
    required this.id,
    required this.userId,
    required this.fromUserId,
    required this.fromUsername,
    required this.fromDisplayName,
    required this.toUserId,
    required this.toUsername,
    required this.toDisplayName,
    required this.status,
    this.userPairKey,
    required this.updatedAt,
    required this.version,
    required this.deleted,
    this.trashedAt,
    required this.createdAt,
  });

  @override
  bool get isDeleted => deleted == 1;

  /// Whether this is an incoming request (user is the recipient)
  bool isIncoming(String currentUserId) => toUserId == currentUserId;

  /// Whether this is an outgoing request (user is the sender)
  bool isOutgoing(String currentUserId) => fromUserId == currentUserId;

  @override
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userId': userId,
      'fromUserId': fromUserId,
      'fromUsername': fromUsername,
      'fromDisplayName': fromDisplayName,
      'toUserId': toUserId,
      'toUsername': toUsername,
      'toDisplayName': toDisplayName,
      'status': status.name,
      if (userPairKey != null) 'userPairKey': userPairKey,
      'updatedAt': updatedAt,
      'version': version,
      'deleted': deleted,
      if (trashedAt != null) 'trashedAt': trashedAt,
      'createdAt': createdAt,
    };
  }

  factory FriendRequestModel.fromJson(Map<String, dynamic> json) {
    return FriendRequestModel(
      id: (json['id'] ?? json['_id']) as String,
      userId: json['userId'] as String,
      fromUserId: json['fromUserId'] as String,
      fromUsername: json['fromUsername'] as String,
      fromDisplayName: json['fromDisplayName'] as String? ?? '',
      toUserId: json['toUserId'] as String,
      toUsername: json['toUsername'] as String,
      toDisplayName: json['toDisplayName'] as String? ?? '',
      status: FriendRequestStatus.values.firstWhere(
        (s) => s.name == json['status'],
        orElse: () => FriendRequestStatus.pending,
      ),
      userPairKey: json['userPairKey'] as String?,
      updatedAt: json['updatedAt'] as int,
      version: json['version'] as int,
      deleted: _parseDeleted(json['deleted']),
      trashedAt: json['trashedAt'] as int?,
      createdAt: json['createdAt'] as int,
    );
  }

  factory FriendRequestModel.create({
    required String id,
    required String userId,
    required String fromUserId,
    required String fromUsername,
    String fromDisplayName = '',
    required String toUserId,
    required String toUsername,
    String toDisplayName = '',
  }) {
    final now = TestClock.now();
    return FriendRequestModel(
      id: id,
      userId: userId,
      fromUserId: fromUserId,
      fromUsername: fromUsername,
      fromDisplayName: fromDisplayName,
      toUserId: toUserId,
      toUsername: toUsername,
      toDisplayName: toDisplayName,
      status: FriendRequestStatus.pending,
      updatedAt: now,
      version: 1,
      deleted: 0,
      createdAt: now,
    );
  }

  FriendRequestModel copyWithStatus(FriendRequestStatus newStatus) {
    return FriendRequestModel(
      id: id,
      userId: userId,
      fromUserId: fromUserId,
      fromUsername: fromUsername,
      fromDisplayName: fromDisplayName,
      toUserId: toUserId,
      toUsername: toUsername,
      toDisplayName: toDisplayName,
      status: newStatus,
      userPairKey: userPairKey,
      updatedAt: TestClock.now(),
      version: version + 1,
      deleted: deleted,
      trashedAt: trashedAt,
      createdAt: createdAt,
    );
  }

  FriendRequestModel softDelete() {
    return FriendRequestModel(
      id: id,
      userId: userId,
      fromUserId: fromUserId,
      fromUsername: fromUsername,
      fromDisplayName: fromDisplayName,
      toUserId: toUserId,
      toUsername: toUsername,
      toDisplayName: toDisplayName,
      status: status,
      userPairKey: userPairKey,
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
      other is FriendRequestModel &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          version == other.version;

  @override
  int get hashCode => id.hashCode ^ version.hashCode;

  @override
  String toString() =>
      'FriendRequestModel(id: $id, from: $fromUsername, to: $toUsername, '
      'status: ${status.name}, v$version)';
}
