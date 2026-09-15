import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/navigation/routes.dart';
import '../../../../core/sync/providers/sync_providers.dart';
import '../../../../core/theme/app_theme.dart';
import '../widgets/friend_card.dart';
import '../../../../shared/widgets/skeletons/skeletons.dart';
import '../../../../core/services/user_facing_error.dart';
import '../../../../core/theme/theme_colors.dart';
import '../../../../l10n/l10n.dart';
import '../../../../shared/widgets/swipe_action.dart';

/// Friends list screen accessible from Settings
class FriendsListScreen extends ConsumerWidget {
  const FriendsListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final friendsAsync = ref.watch(friendsListProvider);
    final pendingCountAsync = ref.watch(pendingRequestCountProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n(context).friends),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        actions: [
          pendingCountAsync.when(
            loading: () => IconButton(
              icon: const Icon(Icons.mail_outline),
              tooltip: l10n(context).friendRequests,
              onPressed: () => context.push(Routes.friendRequests),
            ),
            error: (_, _) => IconButton(
              icon: const Icon(Icons.mail_outline),
              tooltip: l10n(context).friendRequests,
              onPressed: () => context.push(Routes.friendRequests),
            ),
            data: (count) => IconButton(
              icon: Badge(
                isLabelVisible: count > 0,
                label: Text('$count'),
                child: const Icon(Icons.mail_outline),
              ),
              tooltip: l10n(context).friendRequests,
              onPressed: () => context.push(Routes.friendRequests),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.person_search),
            tooltip: l10n(context).findFriends,
            onPressed: () => context.push(Routes.friendsSearch),
          ),
        ],
      ),
      body: friendsAsync.when(
        loading: () => const ListTileSkeletonList(count: 6),
        error: (error, stack) => Center(child: Text(UserFacingError.forLoad(error))),
        data: (friends) {
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(friendsListProvider);
              ref.invalidate(pendingRequestCountProvider);
            },
            child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              // Friend requests banner
              pendingCountAsync.when(
                loading: () => const SizedBox.shrink(),
                error: (_, _) => const SizedBox.shrink(),
                data: (count) {
                  if (count == 0) return const SizedBox.shrink();
                  return _buildRequestsBanner(context, count);
                },
              ),

              // Friends count header
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Row(
                  children: [
                    Text(
                      l10n(context).friends,
                      style:
                          TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '(${friends.length})',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w500,
                        color: context.mutedText,
                      ),
                    ),
                  ],
                ),
              ),

              if (friends.isEmpty)
                _buildEmptyState(context)
              else
                ...friends.map((friend) => Slidable(
                      key: Key(friend.id),
                      endActionPane: ActionPane(
                        motion: const DrawerMotion(),
                        extentRatio: 0.2,
                        children: [
                          buildSwipeAction(
            icon: Icons.person_remove,
            label: l10n(context).moveToTrash,
            accent: AppTheme.error,
            onPressed: (ctx) async {
                              final shouldRemove =
                                  await _showRemoveConfirmation(context);
                              if (!context.mounted) return;
                              if (shouldRemove) {
                                _removeFriend(context, ref, friend.id);
                              }
                            },
          )
                        ],
                      ),
                      child: FriendCard(
                        friendship: friend,
                        onRemove: () async {
                          final shouldRemove =
                              await _showRemoveConfirmation(context);
                          if (!context.mounted) return;
                          if (shouldRemove) {
                            _removeFriend(context, ref, friend.id);
                          }
                        },
                      ),
                    )),
            ],
          ),
          );
        },
      ),
    );
  }

  Widget _buildRequestsBanner(BuildContext context, int count) {
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
        leading: Stack(
          clipBehavior: Clip.none,
          children: [
            const Icon(Icons.person_add, color: AppTheme.teal),
            Positioned(
              top: -4,
              right: -4,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '$count',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
        title: Text(
          '$count pending request${count == 1 ? '' : 's'}',
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            color: AppTheme.teal,
          ),
        ),
        trailing: const Icon(
          Icons.chevron_right,
          color: AppTheme.teal,
        ),
        onTap: () => context.push(Routes.friendRequests),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.people_outline, size: 64, color: context.hintText),
            const SizedBox(height: 16),
            Text(
              l10n(context).noFriendsYet,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w500,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n(context).searchForFriendsByUsernameToConnect,
              style: TextStyle(
                fontSize: 16,
                color: context.mutedText,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => context.push(Routes.friendsSearch),
              icon: const Icon(Icons.person_search),
              label: Text(l10n(context).findFriends),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.teal,
                foregroundColor: AppTheme.onAccent(AppTheme.teal),
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

  Future<bool> _showRemoveConfirmation(BuildContext context) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(l10n(context).removeFriend),
            content: Text(
                l10n(context).areYouSureYouWantToRemoveThisFriend),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(l10n(context).actionCancel),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: TextButton.styleFrom(foregroundColor: context.dangerText),
                child: Text(l10n(context).remove),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _removeFriend(BuildContext context, WidgetRef ref, String friendshipId) async {
    try {
      final api = ref.read(friendsApiServiceProvider);
      await api.removeFriend(friendshipId);
      ref.invalidate(friendsListProvider);
      ref.invalidate(friendCountProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n(context).friendRemoved),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(UserFacingError.message(e, action: 'remove friend')),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }
}
