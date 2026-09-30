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
    // The accent tuned for this theme, not the raw brand teal. On the dark
    // ground the raw value is the same colour as the tint behind it, which is
    // what made this banner read as washed out.
    final accent =
        AppTheme.accentOnTintFor(AppTheme.teal, Theme.of(context).brightness);

    // Material, not a DecoratedBox. A ListTile paints its ink on the nearest
    // Material ancestor, so a coloured box between the two hides every splash —
    // Flutter says so at runtime, and the banner had no tap feedback at all.
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Material(
        color: AppTheme.teal.withValues(alpha: AppTheme.alphaLight),
        borderRadius: BorderRadius.circular(12),
        child: ListTile(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: AppTheme.teal.withValues(alpha: 0.2)),
          ),
          leading: Icon(Icons.group_add, color: accent),
          title: Text(
            l10n(context).joinAGroup,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: accent,
            ),
          ),
          subtitle: Text(l10n(context).enterAGroupCodeToJoin),
          trailing: Icon(Icons.chevron_right, color: accent),
          onTap: () => showJoinGroupDialog(context, ref),
        ),
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
