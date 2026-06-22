import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/navigation/routes.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/sync/providers/sync_providers.dart';
import '../widgets/group_card.dart';
import '../widgets/join_group_dialog.dart';
import '../../../../shared/widgets/skeletons/skeletons.dart';

/// Screen showing list of user's groups
class GroupsListScreen extends ConsumerWidget {
  const GroupsListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupsAsync = ref.watch(groupsListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Groups'),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push(Routes.createGroup),
        backgroundColor: AppTheme.teal,
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: groupsAsync.when(
        loading: () => const ListTileSkeletonList(count: 5),
        error: (error, stack) => Center(child: Text('Error: $error')),
        data: (groups) {
          if (groups.isEmpty) {
            return _buildEmptyState(context, ref);
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Join group banner
              _buildJoinBanner(context, ref),

              // Header
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Row(
                  children: [
                    const Text(
                      'Groups',
                      style:
                          TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '(${groups.length})',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ],
                ),
              ),

              ...groups.map((group) => GroupCard(
                    group: group,
                    onTap: () => context.push('${Routes.groups}/${group.id}'),
                  )),
            ],
          );
        },
      ),
    );
  }

  Widget _buildJoinBanner(BuildContext context, WidgetRef ref) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppTheme.teal.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppTheme.teal.withValues(alpha: 0.2),
        ),
      ),
      child: ListTile(
        leading: const Icon(Icons.group_add, color: AppTheme.teal),
        title: const Text(
          'Join a Group',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: AppTheme.teal,
          ),
        ),
        subtitle: const Text('Enter a group code to join'),
        trailing: const Icon(Icons.chevron_right, color: AppTheme.teal),
        onTap: () => showJoinGroupDialog(context, ref),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, WidgetRef ref) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.groups_outlined, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              'No groups yet',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w500,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Create or join a group to pray together with your community',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade500,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => context.push(Routes.createGroup),
              icon: const Icon(Icons.add),
              label: const Text('Create Group'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.teal,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => showJoinGroupDialog(context, ref),
              icon: const Icon(Icons.group_add),
              label: const Text('Join Group'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.teal,
                side: const BorderSide(color: AppTheme.teal),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

}
