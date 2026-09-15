import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/sync/providers/sync_providers.dart';
import '../widgets/friend_request_card.dart';
import '../../../../shared/widgets/skeletons/skeletons.dart';
import '../../../../core/services/user_facing_error.dart';
import '../../../../core/theme/theme_colors.dart';
import '../../../../l10n/l10n.dart';

/// Screen showing incoming and outgoing friend requests
class FriendRequestsScreen extends ConsumerWidget {
  const FriendRequestsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n(context).friendRequests),
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          elevation: 0,
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Incoming'),
              Tab(text: 'Outgoing'),
            ],
            labelColor: AppTheme.teal,
            unselectedLabelColor: Colors.grey,
            indicatorColor: AppTheme.teal,
          ),
        ),
        body: TabBarView(
          children: [
            _IncomingRequestsTab(),
            _OutgoingRequestsTab(),
          ],
        ),
      ),
    );
  }
}

class _IncomingRequestsTab extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requestsAsync = ref.watch(incomingFriendRequestsProvider);

    return requestsAsync.when(
      loading: () => const ListTileSkeletonList(count: 4),
      error: (error, stack) => Center(child: Text(UserFacingError.forLoad(error))),
      data: (requests) {
        if (requests.isEmpty) {
          return _buildEmptyState(
            context,
            icon: Icons.inbox_outlined,
            title: l10n(context).noIncomingRequests,
            subtitle: l10n(context).friendRequestsYouReceiveWillAppearHere,
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: requests.length,
          itemBuilder: (context, index) {
            final request = requests[index];
            return FriendRequestCard(
              request: request,
              isIncoming: true,
              onAccept: () => _acceptRequest(context, ref, request.id),
              onReject: () => _rejectRequest(context, ref, request.id),
            );
          },
        );
      },
    );
  }

  void _acceptRequest(
      BuildContext context, WidgetRef ref, String requestId) async {
    try {
      final api = ref.read(friendsApiServiceProvider);
      await api.acceptRequest(requestId);
      ref.invalidate(incomingFriendRequestsProvider);
      ref.invalidate(pendingRequestCountProvider);
      ref.invalidate(friendsListProvider);
      ref.invalidate(friendCountProvider);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n(context).friendRequestAccepted),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(UserFacingError.message(e, action: 'accept request')),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _rejectRequest(
      BuildContext context, WidgetRef ref, String requestId) async {
    try {
      final api = ref.read(friendsApiServiceProvider);
      await api.rejectRequest(requestId);
      ref.invalidate(incomingFriendRequestsProvider);
      ref.invalidate(pendingRequestCountProvider);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n(context).requestDeclined),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(UserFacingError.message(e, action: 'decline request')),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }
}

class _OutgoingRequestsTab extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requestsAsync = ref.watch(outgoingFriendRequestsProvider);

    return requestsAsync.when(
      loading: () => const ListTileSkeletonList(count: 4),
      error: (error, stack) => Center(child: Text(UserFacingError.forLoad(error))),
      data: (requests) {
        if (requests.isEmpty) {
          return _buildEmptyState(
            context,
            icon: Icons.outbox_outlined,
            title: l10n(context).noOutgoingRequests,
            subtitle: l10n(context).requestsYouSendWillAppearHere,
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: requests.length,
          itemBuilder: (context, index) {
            final request = requests[index];
            return FriendRequestCard(
              request: request,
              isIncoming: false,
              onCancel: () => _cancelRequest(context, ref, request.id),
            );
          },
        );
      },
    );
  }

  void _cancelRequest(
      BuildContext context, WidgetRef ref, String requestId) async {
    try {
      final api = ref.read(friendsApiServiceProvider);
      await api.cancelRequest(requestId);
      ref.invalidate(outgoingFriendRequestsProvider);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n(context).requestCancelled),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(UserFacingError.message(e, action: 'cancel request')),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }
}

Widget _buildEmptyState(
  BuildContext context, {
  required IconData icon,
  required String title,
  required String subtitle,
}) {
  return Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: context.hintText),
          const SizedBox(height: 16),
          Text(
            title,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w500,
              color: context.mutedText,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 16,
              color: context.mutedText,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );
}
