import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/navigation/routes.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/sync/providers/sync_providers.dart';
import '../widgets/group_card.dart';
import '../widgets/join_group_dialog.dart';
import '../../../../shared/widgets/skeletons/skeletons.dart';
import '../../../../core/services/user_facing_error.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../../../core/theme/theme_colors.dart';
import '../../../../l10n/l10n.dart';

/// Screen showing list of user's groups
class GroupsListScreen extends ConsumerWidget {
  const GroupsListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupsAsync = ref.watch(groupsListProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n(context).myGroups),
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
        error: (error, stack) => Center(child: Text(UserFacingError.forLoad(error))),
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
                    Text(
                      l10n(context).groups,
                      style:
                          TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '(${groups.length})',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w500,
                        color: context.mutedText,
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
        title: Text(
          l10n(context).joinAGroup,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: AppTheme.teal,
          ),
        ),
        subtitle: Text(l10n(context).enterAGroupCodeToJoin),
        trailing: const Icon(Icons.chevron_right, color: AppTheme.teal),
        onTap: () => showJoinGroupDialog(context, ref),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, WidgetRef ref) {
    return EmptyState(
      icon: Icons.groups_outlined,
      title: l10n(context).noGroupsYet,
      message: l10n(context).aGroupIsASetOfPeopleYouPrayWithShareRequests,
          accent: AppTheme.teal,
    );
  }

}
