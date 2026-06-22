import '../models/user_profile_model.dart';
import 'base_social_api_service.dart';

/// Paginated result from user search.
class UserSearchResult {
  final List<UserProfileModel> users;
  final bool hasMore;

  const UserSearchResult({required this.users, required this.hasMore});
}

/// Service for searching users via the server API.
///
/// Calls the server's user search endpoint, which searches across
/// all registered users (not just locally synced ones).
class UserSearchService extends BaseSocialApiService {
  static const int pageSize = 20;

  UserSearchService({
    required super.config,
    required super.authService,
    required super.interceptor,
  });

  /// List all discoverable users (excluding self, blocked, and existing friends).
  Future<UserSearchResult> listUsers({int offset = 0}) async {
    final response = await httpGet('/users/search', queryParams: {
      'limit': '$pageSize',
      'offset': '$offset',
    });
    assertSuccess(response, 'List users');
    return _parseResult(response);
  }

  /// Search for users by username or display name.
  Future<UserSearchResult> searchUsers(String query, {int offset = 0}) async {
    final response = await httpGet('/users/search', queryParams: {
      'q': query,
      'limit': '$pageSize',
      'offset': '$offset',
    });
    assertSuccess(response, 'Search users');
    return _parseResult(response);
  }

  UserSearchResult _parseResult(dynamic response) {
    final body = parseBody(response);
    final list = (body['users'] as List? ?? []).cast<Map<String, dynamic>>();
    final hasMore = body['hasMore'] as bool? ?? false;
    return UserSearchResult(
      users: list.map((u) => UserProfileModel.fromSearchResult(u)).toList(),
      hasMore: hasMore,
    );
  }
}
