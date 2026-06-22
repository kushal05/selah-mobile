import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/sync/providers/sync_providers.dart';
import '../widgets/friend_request_card.dart';
import '../../../../shared/widgets/skeletons/skeletons.dart';

/// Screen showing incoming and outgoing friend requests
class FriendRequestsScreen extends ConsumerWidget {
  const FriendRequestsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Friend Requests'),
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
      error: (error, stack) => Center(child: Text('Error: $error')),
      data: (requests) {
        if (requests.isEmpty) {
          return _buildEmptyState(
            icon: Icons.inbox_outlined,
            title: 'No incoming requests',
            subtitle: 'Friend requests you receive will appear here',
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
          const SnackBar(
            content: Text('Friend request accepted!'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to accept request: $e'),
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
          const SnackBar(
            content: Text('Request declined'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to decline request: $e'),
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
      error: (error, stack) => Center(child: Text('Error: $error')),
      data: (requests) {
        if (requests.isEmpty) {
          return _buildEmptyState(
            icon: Icons.outbox_outlined,
            title: 'No outgoing requests',
            subtitle: 'Requests you send will appear here',
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
          const SnackBar(
            content: Text('Request cancelled'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to cancel request: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }
}

Widget _buildEmptyState({
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
          Icon(icon, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(
            title,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w500,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade500,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );
}
