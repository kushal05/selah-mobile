import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/domain/enums/group_enums.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/sync/models/group_member_model.dart';
import '../../../../core/sync/models/pending_group_member_model.dart';
import '../../../../core/sync/providers/sync_providers.dart';
import '../../../../shared/widgets/skeletons/skeletons.dart';

/// Screen for managing group members (admin only)
class ManageMembersScreen extends ConsumerStatefulWidget {
  final String groupId;

  const ManageMembersScreen({super.key, required this.groupId});

  @override
  ConsumerState<ManageMembersScreen> createState() =>
      _ManageMembersScreenState();
}

class _ManageMembersScreenState extends ConsumerState<ManageMembersScreen> {
  final _usernameController = TextEditingController();
  bool _isAdding = false;

  @override
  void dispose() {
    _usernameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final membersAsync = ref.watch(groupMembersProvider(widget.groupId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Members'),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
      ),
      body: Column(
        children: [
          // Add member section
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              border: Border(
                bottom: BorderSide(color: Colors.grey.shade200),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _usernameController,
                    decoration: InputDecoration(
                      hintText: 'Add member by username...',
                      prefixIcon: const Icon(Icons.person_add_outlined),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: _isAdding ? null : _addMember,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.teal,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 14,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isAdding
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Add'),
                ),
              ],
            ),
          ),

          // Pending approvals section
          _buildPendingSection(),

          // Members list
          Expanded(
            child: membersAsync.when(
              loading: () =>
                  const ListTileSkeletonList(count: 5),
              error: (error, stack) =>
                  Center(child: Text('Error: $error')),
              data: (members) {
                if (members.isEmpty) {
                  return Center(
                    child: Text(
                      'No members',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: members.length,
                  itemBuilder: (context, index) {
                    final member = members[index];
                    return _MemberTile(
                      member: member,
                      onChangeRole: (role) =>
                          _changeRole(member.id, role),
                      onRemove: () => _removeMember(member),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPendingSection() {
    final pendingAsync =
        ref.watch(pendingGroupMembersProvider(widget.groupId));

    return pendingAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (pending) {
        if (pending.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                border: Border(
                  bottom: BorderSide(color: Colors.orange.shade200),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.pending_actions,
                      size: 18, color: Colors.orange.shade700),
                  const SizedBox(width: 8),
                  Text(
                    'Pending Approvals (${pending.length})',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.orange.shade800,
                    ),
                  ),
                ],
              ),
            ),
            ...pending.map((request) => _PendingRequestTile(
                  request: request,
                  onApprove: () => _approveRequest(request),
                  onReject: () => _rejectRequest(request),
                )),
            Divider(height: 1, color: Colors.grey.shade200),
          ],
        );
      },
    );
  }

  Future<void> _approveRequest(PendingGroupMemberModel request) async {
    try {
      final api = ref.read(groupsApiServiceProvider);
      await api.approvePendingMember(
        groupId: request.groupId,
        pendingId: request.id,
      );
      ref.invalidate(pendingGroupMembersProvider(widget.groupId));
      ref.invalidate(groupMembersProvider(widget.groupId));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${request.requestingUsername} approved'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to approve: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _rejectRequest(PendingGroupMemberModel request) async {
    try {
      final api = ref.read(groupsApiServiceProvider);
      await api.rejectPendingMember(
        groupId: request.groupId,
        pendingId: request.id,
      );
      ref.invalidate(pendingGroupMembersProvider(widget.groupId));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${request.requestingUsername} rejected'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to reject: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _addMember() async {
    final username = _usernameController.text.trim();
    if (username.isEmpty) return;

    setState(() => _isAdding = true);

    try {
      // Search for user on server
      final searchService = ref.read(userSearchServiceProvider);
      final results = await searchService.searchUsers(username);

      if (results.users.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('User not found'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        setState(() => _isAdding = false);
        return;
      }

      final targetUser = results.users.first;

      final api = ref.read(groupsApiServiceProvider);
      await api.addMember(
        groupId: widget.groupId,
        memberUserId: targetUser.userId,
      );

      ref.invalidate(groupMembersProvider(widget.groupId));
      _usernameController.clear();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${targetUser.username} added to group'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to add member: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }

    if (mounted) {
      setState(() => _isAdding = false);
    }
  }

  Future<void> _changeRole(String id, GroupMemberRole role) async {
    try {
      final api = ref.read(groupsApiServiceProvider);
      await api.updateMemberRole(
        groupId: widget.groupId,
        memberId: id,
        role: role.name,
      );
      ref.invalidate(groupMembersProvider(widget.groupId));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update role: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _removeMember(GroupMemberModel member) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Member'),
        content: Text(
          'Remove ${member.memberUsername} from this group?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final api = ref.read(groupsApiServiceProvider);
      await api.removeMember(
        groupId: widget.groupId,
        memberId: member.id,
      );
      ref.invalidate(groupMembersProvider(widget.groupId));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${member.memberUsername} removed'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to remove: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }
}

class _MemberTile extends StatelessWidget {
  final GroupMemberModel member;
  final Function(GroupMemberRole) onChangeRole;
  final VoidCallback onRemove;

  const _MemberTile({
    required this.member,
    required this.onChangeRole,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final initial = member.memberUsername.isNotEmpty
        ? member.memberUsername[0].toUpperCase()
        : '?';
    final displayName = member.memberDisplayName.isNotEmpty
        ? member.memberDisplayName
        : member.memberUsername;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor:
                AppTheme.teal.withValues(alpha: 0.1),
            child: Text(
              initial,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppTheme.teal,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '@${member.memberUsername}',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 4),
                _RoleBadge(role: member.role),
              ],
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'remove') {
                onRemove();
              } else {
                final role = GroupMemberRole.values.firstWhere(
                  (r) => r.name == value,
                  orElse: () => GroupMemberRole.member,
                );
                onChangeRole(role);
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'admin',
                child: Text('Set as Admin'),
              ),
              const PopupMenuItem(
                value: 'moderator',
                child: Text('Set as Moderator'),
              ),
              const PopupMenuItem(
                value: 'member',
                child: Text('Set as Member'),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 'remove',
                child: Text(
                  'Remove',
                  style: TextStyle(color: Colors.red.shade600),
                ),
              ),
            ],
            child: Icon(Icons.more_vert, color: Colors.grey.shade400),
          ),
        ],
      ),
    );
  }
}

class _RoleBadge extends StatelessWidget {
  final GroupMemberRole role;
  const _RoleBadge({required this.role});

  @override
  Widget build(BuildContext context) {
    Color color;
    switch (role) {
      case GroupMemberRole.admin:
        color = AppTheme.teal;
      case GroupMemberRole.moderator:
        color = AppTheme.teal;
      case GroupMemberRole.member:
        color = Colors.grey;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        role.displayName,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

class _PendingRequestTile extends StatelessWidget {
  final PendingGroupMemberModel request;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  const _PendingRequestTile({
    required this.request,
    required this.onApprove,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final initial = request.requestingUsername.isNotEmpty
        ? request.requestingUsername[0].toUpperCase()
        : '?';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: Colors.orange.withValues(alpha: 0.1),
            child: Text(
              initial,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: Colors.orange,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  request.requestingUsername,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  'Wants to join',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade500,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.check_circle_outline, color: Colors.green),
            onPressed: onApprove,
            tooltip: 'Approve',
            visualDensity: VisualDensity.compact,
          ),
          IconButton(
            icon: Icon(Icons.cancel_outlined, color: Colors.red.shade400),
            onPressed: onReject,
            tooltip: 'Reject',
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}
