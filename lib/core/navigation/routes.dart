/// Application route paths
/// These paths must never change casually as they are used for:
/// - Deep links
/// - Analytics
/// - State restoration
abstract class Routes {
  /* ───────────── Root ───────────── */
  static const splash = '/';
  static const home = '/home';

  /* ───────────── Auth ───────────── */
  static const onboarding = '/onboarding';
  static const login = '/auth/login';
  static const register = '/auth/register';
  static const forgotPassword = '/auth/forgot-password';
  static const completeProfile = '/complete-profile';

  /* ───────────── Habits ───────────── */
  static const habits = '/home/habits';

  /* ───────────── Settings ───────────── */
  static const settings = '/home/settings';
  static const syncStatus = '/home/settings/sync-status';
  static const devices = '/home/settings/devices';
  static const notificationSettings = '/home/settings/notifications';
  static const changelog = '/home/settings/changelog';
  static const bibleVersions = '/home/settings/bible-versions';

  /* ───────────── Search ───────────── */
  static const search = '/search';

  /* ───────────── Bible ───────────── */
  static const bible = '/bible';
  static const bibleChapter = '/bible/chapter';
  static const bibleHistory = '/bible/history';
  static const bibleSearch = '/bible-search';

  /* ───────────── Notes ───────────── */
  static const notesHome = '/notes';
  static const noteDetail = '/notes/:noteId';
  static const noteHistory = '/notes/:noteId/history';

  /* ───────────── Prayers ───────────── */
  static const prayers = '/prayers';
  static const prayerNew = '/prayers/new';
  static const prayerDetail = '/prayers/:prayerId';

  /* ───────────── Promises ───────────── */
  static const promises = '/promises';
  static const promiseNew = '/promises/new';
  static const promiseDetail = '/promises/:promiseId';
  static const promiseEdit = '/promises/:promiseId/edit';

  /* ───────────── Songs ───────────── */
  static const songs = '/songs';
  static const songNew = '/songs/new';
  static const songSearch = '/songs/search';
  static const songDetail = '/songs/:songId';
  static const songEdit = '/songs/:songId/edit';

  /* ───────────── Pray Today ───────────── */
  static const prayerToday = '/prayers/today';
  static const prayerUpdatesFeed = '/prayers/updates';
  static const prayerList = '/prayers/list';
  static const prayerAnalytics = '/prayers/analytics';

  /* ───────────── Trash ───────────── */
  static const trash = '/home/settings/trash';

  /* ───────────── Tags ───────────── */
  static const tagManagement = '/home/settings/tags';

  /* ───────────── Feedback ───────────── */
  static const feedback = '/home/settings/feedback';
  static const feedbackCreate = '/home/settings/feedback/new';
  static const feedbackThread = '/home/settings/feedback/:threadId';

  /* ───────────── Social (v21: merged People + Friends + Groups) ───────────── */
  static const social = '/social';

  // People (under Social)
  static const socialPeople = '/social/people';
  static const socialPersonNew = '/social/people/new';
  static const socialPersonDetail = '/social/people/:personId';
  static const socialPersonEdit = '/social/people/:personId/edit';

  // Friends (under Social — moved from Settings)
  static const socialFriends = '/social/friends';
  static const socialFriendRequests = '/social/friends/requests';
  static const socialFriendsSearch = '/social/friends/search';
  static const socialProfileSettings = '/social/friends/profile';

  // Groups (under Social — moved from top-level)
  static const socialGroups = '/social/groups';
  static const socialCreateGroup = '/social/groups/new';
  static const socialGroupDetail = '/social/groups/:groupId';
  static const socialGroupMembers = '/social/groups/:groupId/members';
  static const socialGroupContent = '/social/groups/:groupId/content';

  // Shared prayer deep link resolution
  static const socialShareCode = '/social/share/:shareCode';

  /// Generate the collaborators route for a specific prayer
  static String prayerCollaborators(String prayerId) =>
      '/prayers/$prayerId/collaborators';

  // ───────────── Deep Link URL Builders ─────────────

  /// Base URL for deep links.
  static const _deepLinkBase = 'https://selahapp.in';

  /// Build a shareable deep link URL for a note.
  static String noteDeepLink(String noteId) => '$_deepLinkBase/notes/$noteId';

  /// Build a shareable deep link URL for a prayer.
  static String prayerDeepLink(String prayerId) =>
      '$_deepLinkBase/prayers/$prayerId';

  /// Build a shareable deep link URL for a song.
  static String songDeepLink(String songId) => '$_deepLinkBase/songs/$songId';

  /// Build a shareable deep link URL for a promise.
  static String promiseDeepLink(String promiseId) =>
      '$_deepLinkBase/promises/$promiseId';

  /// Build a shareable deep link URL for a group.
  static String groupDeepLink(String groupId) =>
      '$_deepLinkBase/social/groups/$groupId';

  /// Build a shareable deep link URL for a shared prayer.
  static String shareCodeDeepLink(String shareCode) =>
      '$_deepLinkBase/social/share/$shareCode';

  /// Build a shareable deep link URL for a Bible chapter.
  /// Uses the path-based format: /bible/{bookId}/{chapter}?t={translation}&v={verse}
  static String bibleDeepLink(int bookId, int chapter,
      {String? translation, int? verse}) {
    var url = '$_deepLinkBase/bible/$bookId/$chapter';
    final params = <String>[];
    if (translation != null && translation != 'KJV') {
      params.add('t=$translation');
    }
    if (verse != null) params.add('v=$verse');
    if (params.isNotEmpty) url += '?${params.join('&')}';
    return url;
  }

  /* ───────────── Deprecated (kept for backward-compat redirects) ───────────── */

  /// @deprecated Use socialPeople instead
  static const people = '/people';
  /// @deprecated Use socialPersonNew instead
  static const personNew = '/people/new';
  /// @deprecated Use socialPersonDetail instead
  static const personDetail = '/people/:personId';
  /// @deprecated Use socialPersonEdit instead
  static const personEdit = '/people/:personId/edit';

  /// @deprecated Use socialFriends instead
  static const friends = '/home/settings/friends';
  /// @deprecated Use socialFriendRequests instead
  static const friendRequests = '/home/settings/friends/requests';
  /// @deprecated Use socialFriendsSearch instead
  static const friendsSearch = '/home/settings/friends/search';
  /// @deprecated Use socialProfileSettings instead
  static const profileSettings = '/home/settings/friends/profile';

  /// @deprecated Use socialGroups instead
  static const groups = '/groups';
  /// @deprecated Use socialCreateGroup instead
  static const createGroup = '/groups/new';
  /// @deprecated Use socialGroupDetail instead
  static const groupDetail = '/groups/:groupId';
  /// @deprecated Use socialGroupMembers instead
  static const groupMembers = '/groups/:groupId/members';
}
