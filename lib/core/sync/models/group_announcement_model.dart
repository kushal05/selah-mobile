import 'sync_entity.dart';
import '../../testing/test_clock.dart';

/// Domain model for GroupAnnouncement
///
/// Represents an announcement posted to a group
class GroupAnnouncementModel implements SyncEntity {
  @override
  final String id;

  /// Group ID
  final String groupId;

  /// Announcement title
  final String title;

  /// Announcement content
  final String content;

  /// Author's user ID
  final String authorUserId;

  /// Author's username (denormalized)
  final String authorUsername;

  /// Whether this announcement is pinned
  final bool pinned;

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

  const GroupAnnouncementModel({
    required this.id,
    required this.groupId,
    required this.title,
    required this.content,
    required this.authorUserId,
    required this.authorUsername,
    required this.pinned,
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
      'title': title,
      'content': content,
      'authorUserId': authorUserId,
      'authorUsername': authorUsername,
      'pinned': pinned,
      'userId': userId,
      'updatedAt': updatedAt,
      'version': version,
      'deleted': deleted,
      if (trashedAt != null) 'trashedAt': trashedAt,
      'createdAt': createdAt,
    };
  }

  factory GroupAnnouncementModel.fromJson(Map<String, dynamic> json) {
    return GroupAnnouncementModel(
      id: (json['id'] ?? json['_id']) as String,
      groupId: json['groupId'] as String,
      title: json['title'] as String,
      content: json['content'] as String? ?? '',
      authorUserId: json['authorUserId'] as String,
      authorUsername: json['authorUsername'] as String? ?? '',
      pinned: _parseBool(json['pinned']),
      userId: json['userId'] as String,
      updatedAt: json['updatedAt'] as int,
      version: json['version'] as int,
      deleted: _parseDeleted(json['deleted']),
      trashedAt: json['trashedAt'] as int?,
      createdAt: json['createdAt'] as int,
    );
  }

  factory GroupAnnouncementModel.create({
    required String id,
    required String groupId,
    required String title,
    String content = '',
    required String authorUserId,
    required String authorUsername,
    required String userId,
    bool pinned = false,
  }) {
    final now = TestClock.now();
    return GroupAnnouncementModel(
      id: id,
      groupId: groupId,
      title: title,
      content: content,
      authorUserId: authorUserId,
      authorUsername: authorUsername,
      pinned: pinned,
      userId: userId,
      updatedAt: now,
      version: 1,
      deleted: 0,
      createdAt: now,
    );
  }

  GroupAnnouncementModel copyWithUpdate({
    String? title,
    String? content,
    bool? pinned,
  }) {
    return GroupAnnouncementModel(
      id: id,
      groupId: groupId,
      title: title ?? this.title,
      content: content ?? this.content,
      authorUserId: authorUserId,
      authorUsername: authorUsername,
      pinned: pinned ?? this.pinned,
      userId: userId,
      updatedAt: TestClock.now(),
      version: version + 1,
      deleted: deleted,
      trashedAt: trashedAt,
      createdAt: createdAt,
    );
  }

  GroupAnnouncementModel softDelete() {
    return GroupAnnouncementModel(
      id: id,
      groupId: groupId,
      title: title,
      content: content,
      authorUserId: authorUserId,
      authorUsername: authorUsername,
      pinned: pinned,
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

  static bool _parseBool(dynamic value) {
    if (value is bool) return value;
    if (value is int) return value == 1;
    return false;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GroupAnnouncementModel &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          version == other.version;

  @override
  int get hashCode => id.hashCode ^ version.hashCode;

  @override
  String toString() =>
      'GroupAnnouncementModel(id: $id, title: $title, v$version)';
}
