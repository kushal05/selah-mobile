import '../models/group_announcement_model.dart';
import '../models/group_feed_item.dart';
import '../models/group_prayer_model.dart';
import 'base_social_api_service.dart';

/// Online-required API service for group prayers and announcements.
class GroupContentApiService extends BaseSocialApiService {
  GroupContentApiService({
    required super.config,
    required super.authService,
    required super.interceptor,
  });

  // ==================== GROUP PRAYERS ====================

  /// Get all prayers for a group.
  Future<List<GroupPrayerModel>> getGroupPrayers(String groupId) async {
    final response = await httpGet('/groups/$groupId/prayers');
    assertSuccess(response, 'Get group prayers');
    final list = parseList(response, 'prayers');
    return list.map(GroupPrayerModel.fromJson).toList();
  }

  /// Add a prayer to a group.
  Future<GroupPrayerModel> addGroupPrayer({
    required String groupId,
    required String prayerId,
  }) async {
    final response = await httpPost('/groups/$groupId/prayers', body: {
      'prayerId': prayerId,
    });
    assertSuccess(response, 'Add group prayer');
    final body = parseBody(response);
    return GroupPrayerModel.fromJson(
        body['prayer'] as Map<String, dynamic>);
  }

  /// Remove a prayer from a group.
  Future<void> removeGroupPrayer({
    required String groupId,
    required String groupPrayerId,
  }) async {
    final response =
        await httpDelete('/groups/$groupId/prayers/$groupPrayerId');
    assertSuccess(response, 'Remove group prayer');
  }

  // ==================== ANNOUNCEMENTS ====================

  /// Get all announcements for a group.
  Future<List<GroupAnnouncementModel>> getGroupAnnouncements(
      String groupId) async {
    final response = await httpGet('/groups/$groupId/announcements');
    assertSuccess(response, 'Get announcements');
    final list = parseList(response, 'announcements');
    return list.map(GroupAnnouncementModel.fromJson).toList();
  }

  /// Create an announcement.
  Future<GroupAnnouncementModel> createAnnouncement({
    required String groupId,
    required String title,
    String content = '',
  }) async {
    final response =
        await httpPost('/groups/$groupId/announcements', body: {
      'title': title,
      'content': content,
    });
    assertSuccess(response, 'Create announcement');
    final body = parseBody(response);
    return GroupAnnouncementModel.fromJson(
        body['announcement'] as Map<String, dynamic>);
  }

  /// Update an announcement.
  Future<GroupAnnouncementModel> updateAnnouncement({
    required String groupId,
    required String announcementId,
    String? title,
    String? content,
    bool? pinned,
  }) async {
    final body = <String, dynamic>{};
    if (title != null) body['title'] = title;
    if (content != null) body['content'] = content;
    if (pinned != null) body['pinned'] = pinned;

    final response = await httpPut(
      '/groups/$groupId/announcements/$announcementId',
      body: body,
    );
    assertSuccess(response, 'Update announcement');
    final data = parseBody(response);
    return GroupAnnouncementModel.fromJson(
        data['announcement'] as Map<String, dynamic>);
  }

  /// Delete an announcement.
  Future<void> deleteAnnouncement({
    required String groupId,
    required String announcementId,
  }) async {
    final response = await httpDelete(
        '/groups/$groupId/announcements/$announcementId');
    assertSuccess(response, 'Delete announcement');
  }

  // ==================== FEED ====================

  /// Get the unified activity feed for a group (prayers + announcements),
  /// sorted by creation time descending.
  ///
  /// Each item has a [type] field of "prayer" or "announcement".
  /// Prayer items include: id, groupId, prayerId, userId, createdAt.
  /// Announcement items include: id, groupId, title, content, pinned,
  /// authorUserId, authorUsername, userId, createdAt.
  Future<List<GroupFeedItem>> getGroupFeed(
    String groupId, {
    int limit = 20,
    int? before,
  }) async {
    final response = await httpGet(
      '/groups/$groupId/feed',
      queryParams: {
        'limit': limit.toString(),
        if (before != null) 'before': before.toString(),
      },
    );
    assertSuccess(response, 'Get group feed');
    final body = parseBody(response);
    final raw = body['feed'] as List? ?? [];
    return raw
        .cast<Map<String, dynamic>>()
        .map(GroupFeedItem.fromJson)
        .toList();
  }
}
