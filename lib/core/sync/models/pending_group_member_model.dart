import 'sync_entity.dart';
import '../../testing/test_clock.dart';

enum PendingMemberStatus {
  pending,
  approved,
  rejected;

  static PendingMemberStatus fromString(String value) {
    switch (value) {
      case 'approved':
        return PendingMemberStatus.approved;
      case 'rejected':
        return PendingMemberStatus.rejected;
      default:
        return PendingMemberStatus.pending;
    }
  }
}

/// Model for a pending group membership request.
class PendingGroupMemberModel implements SyncEntity {
  @override
  final String id;
  final String groupId;
  final String requestingUserId;
  final String requestingUsername;
  final PendingMemberStatus status;
  final String userId;
  @override
  final int updatedAt;
  @override
  final int version;
  final int deleted;
  @override
  final int? trashedAt;
  final int createdAt;

  const PendingGroupMemberModel({
    required this.id,
    required this.groupId,
    required this.requestingUserId,
    this.requestingUsername = '',
    this.status = PendingMemberStatus.pending,
    required this.userId,
    required this.updatedAt,
    this.version = 1,
    this.deleted = 0,
    this.trashedAt,
    required this.createdAt,
  });

  factory PendingGroupMemberModel.create({
    required String id,
    required String groupId,
    required String requestingUserId,
    String requestingUsername = '',
    required String userId,
  }) {
    final now = TestClock.now();
    return PendingGroupMemberModel(
      id: id,
      groupId: groupId,
      requestingUserId: requestingUserId,
      requestingUsername: requestingUsername,
      status: PendingMemberStatus.pending,
      userId: userId,
      updatedAt: now,
      version: 1,
      deleted: 0,
      createdAt: now,
    );
  }

  @override
  bool get isDeleted => deleted == 1;
  bool get isPending => status == PendingMemberStatus.pending;
  bool get isApproved => status == PendingMemberStatus.approved;
  bool get isRejected => status == PendingMemberStatus.rejected;

  PendingGroupMemberModel copyWithUpdate({
    PendingMemberStatus? status,
  }) {
    return PendingGroupMemberModel(
      id: id,
      groupId: groupId,
      requestingUserId: requestingUserId,
      requestingUsername: requestingUsername,
      status: status ?? this.status,
      userId: userId,
      updatedAt: TestClock.now(),
      version: version + 1,
      deleted: deleted,
      trashedAt: trashedAt,
      createdAt: createdAt,
    );
  }

  PendingGroupMemberModel softDelete() {
    return PendingGroupMemberModel(
      id: id,
      groupId: groupId,
      requestingUserId: requestingUserId,
      requestingUsername: requestingUsername,
      status: status,
      userId: userId,
      updatedAt: TestClock.now(),
      version: version + 1,
      deleted: 1,
      trashedAt: trashedAt,
      createdAt: createdAt,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'groupId': groupId,
      'requestingUserId': requestingUserId,
      'requestingUsername': requestingUsername,
      'status': status.name,
      'userId': userId,
      'updatedAt': updatedAt,
      'version': version,
      'deleted': deleted,
      if (trashedAt != null) 'trashedAt': trashedAt,
      'createdAt': createdAt,
    };
  }

  /// Parses deleted flag that may be bool (from API) or int (from local DB).
  static int _parseDeleted(dynamic value) {
    if (value is bool) return value ? 1 : 0;
    if (value is int) return value;
    return 0;
  }

  factory PendingGroupMemberModel.fromJson(Map<String, dynamic> json) {
    return PendingGroupMemberModel(
      id: (json['id'] ?? json['_id']) as String,
      groupId: json['groupId'] as String,
      requestingUserId: json['requestingUserId'] as String,
      requestingUsername: json['requestingUsername'] as String? ?? '',
      status: PendingMemberStatus.fromString(json['status'] as String? ?? 'pending'),
      userId: json['userId'] as String,
      updatedAt: json['updatedAt'] as int,
      version: json['version'] as int? ?? 1,
      deleted: _parseDeleted(json['deleted']),
      trashedAt: json['trashedAt'] as int?,
      createdAt: json['createdAt'] as int,
    );
  }
}
