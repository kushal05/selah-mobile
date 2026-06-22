import '../../domain/enums/group_enums.dart';
import '../models/group_member_model.dart';
import '../models/group_model.dart';
import '../models/pending_group_member_model.dart';
import 'base_social_api_service.dart';

/// Online-required API service for groups, members, and pending members.
class GroupsApiService extends BaseSocialApiService {
  GroupsApiService({
    required super.config,
    required super.authService,
    required super.interceptor,
  });

  // ==================== GROUPS ====================

  /// Get all groups for the current user.
  Future<List<GroupModel>> getGroups() async {
    final response = await httpGet('/groups');
    assertSuccess(response, 'Get groups');
    final list = parseList(response, 'groups');
    return list.map(GroupModel.fromJson).toList();
  }

  /// Get group count.
  Future<int> getGroupCount() async {
    final response = await httpGet('/groups/count');
    assertSuccess(response, 'Get group count');
    final body = parseBody(response);
    return body['count'] as int;
  }

  /// Get a single group by ID.
  Future<GroupModel?> getGroupById(String groupId) async {
    final response = await httpGet('/groups/$groupId');
    if (response.statusCode == 404) return null;
    assertSuccess(response, 'Get group');
    final body = parseBody(response);
    return GroupModel.fromJson(body['group'] as Map<String, dynamic>);
  }

  /// Create a new group. Server auto-adds creator as admin.
  Future<GroupModel> createGroup({
    required String name,
    String description = '',
    required GroupType groupType,
    required GroupJoinPolicy joinPolicy,
  }) async {
    final response = await httpPost('/groups', body: {
      'name': name,
      'description': description,
      'groupType': groupType.name,
      'joinPolicy': joinPolicy.name,
    });
    assertSuccess(response, 'Create group');
    final body = parseBody(response);
    return GroupModel.fromJson(body['group'] as Map<String, dynamic>);
  }

  /// Update group details.
  Future<GroupModel> updateGroup({
    required String groupId,
    String? name,
    String? description,
    GroupType? groupType,
    GroupJoinPolicy? joinPolicy,
  }) async {
    final body = <String, dynamic>{};
    if (name != null) body['name'] = name;
    if (description != null) body['description'] = description;
    if (groupType != null) body['groupType'] = groupType.name;
    if (joinPolicy != null) body['joinPolicy'] = joinPolicy.name;

    final response = await httpPut('/groups/$groupId', body: body);
    assertSuccess(response, 'Update group');
    final data = parseBody(response);
    return GroupModel.fromJson(data['group'] as Map<String, dynamic>);
  }

  /// Delete a group.
  Future<void> deleteGroup(String groupId) async {
    final response = await httpDelete('/groups/$groupId');
    assertSuccess(response, 'Delete group');
  }

  // ==================== MEMBERS ====================

  /// Get all members for a group.
  Future<List<GroupMemberModel>> getGroupMembers(String groupId) async {
    final response = await httpGet('/groups/$groupId/members');
    assertSuccess(response, 'Get group members');
    final list = parseList(response, 'members');
    return list.map(GroupMemberModel.fromJson).toList();
  }

  /// Add a member to a group.
  Future<GroupMemberModel> addMember({
    required String groupId,
    required String memberUserId,
    String? role,
  }) async {
    final body = <String, dynamic>{
      'memberUserId': memberUserId,
    };
    if (role != null) body['role'] = role;

    final response =
        await httpPost('/groups/$groupId/members', body: body);
    assertSuccess(response, 'Add member');
    final data = parseBody(response);
    return GroupMemberModel.fromJson(
        data['member'] as Map<String, dynamic>);
  }

  /// Update a member's role.
  Future<void> updateMemberRole({
    required String groupId,
    required String memberId,
    required String role,
  }) async {
    final response = await httpPut(
      '/groups/$groupId/members/$memberId/role',
      body: {'role': role},
    );
    assertSuccess(response, 'Update member role');
  }

  /// Remove a member from a group.
  Future<void> removeMember({
    required String groupId,
    required String memberId,
  }) async {
    final response =
        await httpDelete('/groups/$groupId/members/$memberId');
    assertSuccess(response, 'Remove member');
  }

  /// Leave a group (current user).
  Future<void> leaveGroup(String groupId) async {
    final response =
        await httpDelete('/groups/$groupId/members/me');
    assertSuccess(response, 'Leave group');
  }

  // ==================== PENDING MEMBERS ====================

  /// Get pending member requests for a group.
  Future<List<PendingGroupMemberModel>> getPendingMembers(
      String groupId) async {
    final response = await httpGet('/groups/$groupId/pending');
    assertSuccess(response, 'Get pending members');
    final list = parseList(response, 'pending');
    return list.map(PendingGroupMemberModel.fromJson).toList();
  }

  /// Approve a pending member request.
  Future<void> approvePendingMember({
    required String groupId,
    required String pendingId,
  }) async {
    final response = await httpPut(
        '/groups/$groupId/pending/$pendingId/approve');
    assertSuccess(response, 'Approve pending member');
  }

  /// Reject a pending member request.
  Future<void> rejectPendingMember({
    required String groupId,
    required String pendingId,
  }) async {
    final response = await httpPut(
        '/groups/$groupId/pending/$pendingId/reject');
    assertSuccess(response, 'Reject pending member');
  }
}
