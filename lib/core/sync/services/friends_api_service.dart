import '../models/blocked_user_model.dart';
import '../models/friend_request_model.dart';
import '../models/friendship_model.dart';
import '../models/user_profile_model.dart';
import '../models/user_stats_model.dart';
import 'base_social_api_service.dart';

/// Online-required API service for user profiles, friendships,
/// friend requests, and blocked users.
class FriendsApiService extends BaseSocialApiService {
  FriendsApiService({
    required super.config,
    required super.authService,
    required super.interceptor,
  });

  // ==================== PROFILE ====================

  /// Get current user's profile from server.
  Future<UserProfileModel?> getCurrentProfile() async {
    final response = await httpGet('/profile');
    if (response.statusCode == 404) return null;
    assertSuccess(response, 'Get profile');
    final body = parseBody(response);
    final profile = body['profile'] as Map<String, dynamic>?;
    if (profile == null) return null;
    return UserProfileModel.fromJson(profile);
  }

  /// Update current user's profile.
  Future<UserProfileModel> updateProfile({
    String? username,
    String? displayName,
    String? bio,
    String? imageUrl,
    bool? friendRequestsEnabled,
  }) async {
    final body = <String, dynamic>{};
    if (username != null) body['username'] = username;
    if (displayName != null) body['displayName'] = displayName;
    if (bio != null) body['bio'] = bio;
    if (imageUrl != null) body['imageUrl'] = imageUrl;
    if (friendRequestsEnabled != null) {
      body['friendRequestsEnabled'] = friendRequestsEnabled;
    }

    final response = await httpPut('/profile', body: body);
    assertSuccess(response, 'Update profile');
    final data = parseBody(response);
    return UserProfileModel.fromJson(data['profile'] as Map<String, dynamic>);
  }

  // ==================== FRIENDSHIPS ====================

  /// Get all friends for the current user.
  Future<List<FriendshipModel>> getFriends() async {
    final response = await httpGet('/friends');
    assertSuccess(response, 'Get friends');
    final list = parseList(response, 'friends');
    return list.map(FriendshipModel.fromJson).toList();
  }

  /// Get friend count.
  Future<int> getFriendCount() async {
    final response = await httpGet('/friends/count');
    assertSuccess(response, 'Get friend count');
    final body = parseBody(response);
    return body['count'] as int;
  }

  /// Remove a friend.
  Future<void> removeFriend(String friendshipId) async {
    final response = await httpDelete('/friends/$friendshipId');
    assertSuccess(response, 'Remove friend');
  }

  // ==================== FRIEND REQUESTS ====================

  /// Get incoming friend requests.
  Future<List<FriendRequestModel>> getIncomingRequests() async {
    final response = await httpGet('/friend-requests/incoming');
    assertSuccess(response, 'Get incoming requests');
    final list = parseList(response, 'requests');
    return list.map(FriendRequestModel.fromJson).toList();
  }

  /// Get outgoing friend requests.
  Future<List<FriendRequestModel>> getOutgoingRequests() async {
    final response = await httpGet('/friend-requests/outgoing');
    assertSuccess(response, 'Get outgoing requests');
    final list = parseList(response, 'requests');
    return list.map(FriendRequestModel.fromJson).toList();
  }

  /// Get pending incoming request count.
  Future<int> getPendingRequestCount() async {
    final response = await httpGet('/friend-requests/count');
    assertSuccess(response, 'Get request count');
    final body = parseBody(response);
    return body['count'] as int;
  }

  /// Send a friend request. Server knows the sender from auth token.
  Future<FriendRequestModel> sendFriendRequest({
    required String toUserId,
  }) async {
    final response = await httpPost('/friend-requests', body: {
      'toUserId': toUserId,
    });
    assertSuccess(response, 'Send friend request');
    final body = parseBody(response);
    return FriendRequestModel.fromJson(body['request'] as Map<String, dynamic>);
  }

  /// Accept a friend request. Server creates bidirectional friendship.
  Future<void> acceptRequest(String requestId) async {
    final response =
        await httpPut('/friend-requests/$requestId/accept');
    assertSuccess(response, 'Accept friend request');
  }

  /// Reject a friend request.
  Future<void> rejectRequest(String requestId) async {
    final response =
        await httpPut('/friend-requests/$requestId/reject');
    assertSuccess(response, 'Reject friend request');
  }

  /// Cancel (delete) a sent friend request.
  Future<void> cancelRequest(String requestId) async {
    final response = await httpDelete('/friend-requests/$requestId');
    assertSuccess(response, 'Cancel friend request');
  }

  // ==================== BLOCKED USERS ====================

  /// Get list of blocked users.
  Future<List<BlockedUserModel>> getBlockedUsers() async {
    final response = await httpGet('/blocked-users');
    assertSuccess(response, 'Get blocked users');
    final list = parseList(response, 'blockedUsers');
    return list.map(BlockedUserModel.fromJson).toList();
  }

  /// Block a user.
  Future<BlockedUserModel> blockUser({
    required String blockedUserId,
    required String blockedUsername,
  }) async {
    final response = await httpPost('/blocked-users', body: {
      'blockedUserId': blockedUserId,
      'blockedUsername': blockedUsername,
    });
    assertSuccess(response, 'Block user');
    final body = parseBody(response);
    return BlockedUserModel.fromJson(
        body['blockedUser'] as Map<String, dynamic>);
  }

  /// Unblock a user.
  Future<void> unblockUser(String blockedUserId) async {
    final response = await httpDelete('/blocked-users/$blockedUserId');
    assertSuccess(response, 'Unblock user');
  }

  // ==================== USER STATS ====================

  /// Get current user's usage statistics.
  Future<UserStatsModel> getUserStats() async {
    final response = await httpGet('/user-stats');
    assertSuccess(response, 'Get user stats');
    final body = parseBody(response);
    return UserStatsModel.fromJson(body['stats'] as Map<String, dynamic>);
  }
}
