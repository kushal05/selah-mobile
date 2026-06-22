import 'dart:convert';

import '../models/group_model.dart';
import 'base_social_api_service.dart';

/// Service for looking up and joining groups via the server API.
///
/// Group data lives on other users' devices, so a local DB lookup
/// won't find groups created by other users. This service calls the
/// server to look up groups by join code across all users.
class GroupJoinService extends BaseSocialApiService {
  GroupJoinService({
    required super.config,
    required super.authService,
    required super.interceptor,
  });

  /// Look up a group by its join code via the server.
  ///
  /// Returns the [GroupModel] if found, or `null` if the code is invalid.
  Future<GroupModel?> lookupByCode(String joinCode) async {
    final code = Uri.encodeComponent(joinCode.toUpperCase().trim());
    final response = await httpGet('/groups/join/$code');

    if (response.statusCode == 200) {
      final body = parseBody(response);
      final groupJson = body['group'] as Map<String, dynamic>?;
      if (groupJson == null) return null;
      return GroupModel.fromJson(groupJson);
    }

    if (response.statusCode == 404) {
      return null;
    }

    throw Exception('Group lookup failed: HTTP ${response.statusCode}');
  }

  /// Join a group via the server.
  ///
  /// The server creates the membership and returns the group data.
  Future<GroupJoinResult> joinGroup(String joinCode) async {
    final response = await httpPost('/groups/join', body: {
      'joinCode': joinCode.toUpperCase().trim(),
    });

    if (response.statusCode == 200) {
      final body = parseBody(response);
      final groupJson = body['group'] as Map<String, dynamic>;
      final group = GroupModel.fromJson(groupJson);
      final alreadyMember = body['alreadyMember'] as bool? ?? false;
      return GroupJoinResult(group: group, alreadyMember: alreadyMember);
    }

    if (response.statusCode == 404) {
      return GroupJoinResult.notFound();
    }

    if (response.statusCode == 409) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final groupJson = body['group'] as Map<String, dynamic>?;
      if (groupJson != null) {
        return GroupJoinResult(
          group: GroupModel.fromJson(groupJson),
          alreadyMember: true,
        );
      }
    }

    throw Exception('Join group failed: HTTP ${response.statusCode}');
  }
}

/// Result of a group join attempt.
class GroupJoinResult {
  final GroupModel? group;
  final bool alreadyMember;
  final bool notFound;

  GroupJoinResult({
    required this.group,
    this.alreadyMember = false,
  }) : notFound = false;

  GroupJoinResult.notFound()
      : group = null,
        alreadyMember = false,
        notFound = true;
}
