/// A single item in the group activity feed.
///
/// Items come in two flavours:
/// - [GroupFeedItemType.prayer]       — a prayer shared with the group.
/// - [GroupFeedItemType.announcement] — a text announcement posted by an admin.
class GroupFeedItem {
  final String id;
  final GroupFeedItemType type;
  final String groupId;
  final int createdAt;

  // Prayer-specific fields
  final String? prayerId;
  final String? userId;

  // Announcement-specific fields
  final String? title;
  final String? content;
  final bool? pinned;
  final String? authorUserId;
  final String? authorUsername;

  const GroupFeedItem({
    required this.id,
    required this.type,
    required this.groupId,
    required this.createdAt,
    this.prayerId,
    this.userId,
    this.title,
    this.content,
    this.pinned,
    this.authorUserId,
    this.authorUsername,
  });

  factory GroupFeedItem.fromJson(Map<String, dynamic> json) {
    final typeStr = json['type'] as String? ?? 'prayer';
    final type = typeStr == 'announcement'
        ? GroupFeedItemType.announcement
        : GroupFeedItemType.prayer;

    return GroupFeedItem(
      id: json['id'] as String,
      type: type,
      groupId: json['groupId'] as String? ?? '',
      createdAt: (json['createdAt'] as num).toInt(),
      prayerId: json['prayerId'] as String?,
      userId: json['userId'] as String?,
      title: json['title'] as String?,
      content: json['content'] as String?,
      pinned: json['pinned'] as bool?,
      authorUserId: json['authorUserId'] as String?,
      authorUsername: json['authorUsername'] as String?,
    );
  }

  bool get isPrayer => type == GroupFeedItemType.prayer;
  bool get isAnnouncement => type == GroupFeedItemType.announcement;
}

enum GroupFeedItemType { prayer, announcement }
