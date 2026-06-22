/// Maps FCM data payload fields to go_router path strings.
///
/// The backend sends a `type` field (matching notification categories defined
/// in `domain/push.go`) and optional `id` / `groupId` / `action` fields.
class NotificationRouter {
  NotificationRouter._();

  /// Returns the go_router path to navigate to for the given FCM data payload,
  /// or null if no matching route exists.
  static String? routeFrom(Map<String, dynamic> data) {
    final type = data['type'] as String?;
    if (type == null) return null;

    switch (type) {
      // ── Social: Friends ───────────────────────────────────────────────
      case 'social_friend_request':
        return '/social/friends/requests';

      case 'social_friendship':
        return '/social/friends';

      // ── Social: Groups ────────────────────────────────────────────────
      case 'social_group_invite':
      case 'social_group_member':
      case 'social_group_role':
        final groupId = data['groupId'] as String?;
        if (groupId != null) return '/social/groups/$groupId';
        return '/social/groups';

      case 'social_group_announcement':
      case 'social_group_prayer':
        final groupId = data['groupId'] as String?;
        if (groupId != null) return '/social/groups/$groupId';
        return '/social';

      // ── Prayer Collaborators ──────────────────────────────────────────
      case 'prayer_collaborator':
        final prayerId = data['id'] as String?;
        if (prayerId != null) return '/prayers/$prayerId/collaborators';
        return '/prayers';

      // ── Prayer Reminder ───────────────────────────────────────────────
      case 'habit_prayer_reminder':
        final prayerId = data['id'] as String?;
        if (prayerId != null) return '/prayers/$prayerId';
        return '/prayers/today';

      // ── Daily Habits ──────────────────────────────────────────────────
      case 'habit_meditation':
        return '/home';

      case 'habit_bible_reading':
        return '/bible';

      case 'habit_journal':
        return '/notes';

      default:
        return null;
    }
  }
}
