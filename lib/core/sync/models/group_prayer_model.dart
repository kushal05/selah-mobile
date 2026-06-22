import 'sync_entity.dart';
import '../../testing/test_clock.dart';

/// Domain model for GroupPrayer
///
/// Links a prayer to a group for shared prayer lists
class GroupPrayerModel implements SyncEntity {
  @override
  final String id;

  /// Group ID
  final String groupId;

  /// Prayer ID
  final String prayerId;

  /// User who added this prayer to the group
  final String addedByUserId;

  /// Username of the user who added (denormalized)
  final String addedByUsername;

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

  const GroupPrayerModel({
    required this.id,
    required this.groupId,
    required this.prayerId,
    required this.addedByUserId,
    required this.addedByUsername,
    required this.userId,
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
      'groupId': groupId,
      'prayerId': prayerId,
      'addedByUserId': addedByUserId,
      'addedByUsername': addedByUsername,
      'userId': userId,
      'updatedAt': updatedAt,
      'version': version,
      'deleted': deleted,
      if (trashedAt != null) 'trashedAt': trashedAt,
      'createdAt': createdAt,
    };
  }

  factory GroupPrayerModel.fromJson(Map<String, dynamic> json) {
    return GroupPrayerModel(
      id: (json['id'] ?? json['_id']) as String,
      groupId: json['groupId'] as String,
      prayerId: json['prayerId'] as String,
      addedByUserId: json['addedByUserId'] as String,
      addedByUsername: json['addedByUsername'] as String? ?? '',
      userId: json['userId'] as String,
      updatedAt: json['updatedAt'] as int,
      version: json['version'] as int,
      deleted: _parseDeleted(json['deleted']),
      trashedAt: json['trashedAt'] as int?,
      createdAt: json['createdAt'] as int,
    );
  }

  factory GroupPrayerModel.create({
    required String id,
    required String groupId,
    required String prayerId,
    required String addedByUserId,
    required String addedByUsername,
    required String userId,
  }) {
    final now = TestClock.now();
    return GroupPrayerModel(
      id: id,
      groupId: groupId,
      prayerId: prayerId,
      addedByUserId: addedByUserId,
      addedByUsername: addedByUsername,
      userId: userId,
      updatedAt: now,
      version: 1,
      deleted: 0,
      createdAt: now,
    );
  }

  GroupPrayerModel softDelete() {
    return GroupPrayerModel(
      id: id,
      groupId: groupId,
      prayerId: prayerId,
      addedByUserId: addedByUserId,
      addedByUsername: addedByUsername,
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
      other is GroupPrayerModel &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          version == other.version;

  @override
  int get hashCode => id.hashCode ^ version.hashCode;

  @override
  String toString() =>
      'GroupPrayerModel(id: $id, groupId: $groupId, prayerId: $prayerId, v$version)';
}
