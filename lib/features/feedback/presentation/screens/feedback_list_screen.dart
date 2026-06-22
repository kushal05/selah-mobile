import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/navigation/routes.dart';
import '../../../../core/sync/models/feedback_thread_model.dart';
import '../../../../core/sync/providers/sync_providers.dart';

/// Screen showing all feedback threads for the current user
class FeedbackListScreen extends ConsumerWidget {
  const FeedbackListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final threadsAsync = ref.watch(feedbackThreadsStreamProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Send Feedback'),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
      ),
      body: threadsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Error loading feedback', style: TextStyle(color: Colors.grey.shade600)),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => ref.invalidate(feedbackThreadsStreamProvider),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
        data: (threads) {
          if (threads.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.feedback_outlined, size: 64, color: Colors.grey.shade400),
                  const SizedBox(height: 16),
                  Text(
                    'No feedback yet',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Tap + to send your first feedback',
                    style: TextStyle(color: Colors.grey.shade500),
                  ),
                ],
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: threads.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final thread = threads[index];
              return _FeedbackThreadTile(thread: thread);
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push(Routes.feedbackCreate),
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _FeedbackThreadTile extends StatelessWidget {
  final FeedbackThreadModel thread;

  const _FeedbackThreadTile({required this.thread});

  @override
  Widget build(BuildContext context) {
    final status = thread.statusEnum;
    final category = thread.categoryEnum;
    final hasUnread = thread.hasUnread;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Stack(
        children: [
          CircleAvatar(
            backgroundColor: _categoryColor(category).withValues(alpha: 0.15),
            child: Icon(
              _categoryIcon(category),
              color: _categoryColor(category),
              size: 20,
            ),
          ),
          // Unread dot
          if (hasUnread)
            Positioned(
              right: 0,
              top: 0,
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    width: 1.5,
                  ),
                ),
              ),
            ),
        ],
      ),
      title: Text(
        thread.subject,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight: hasUnread ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
      subtitle: Row(
        children: [
          _StatusBadge(status: status),
          const SizedBox(width: 8),
          Text(
            category.displayName,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          const Spacer(),
          if (thread.lastMessageAt != null)
            Text(
              _formatTime(thread.lastMessageAt!),
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
            ),
        ],
      ),
      trailing: const Icon(Icons.chevron_right, size: 20),
      onTap: () {
        final path = Routes.feedbackThread.replaceFirst(':threadId', thread.id);
        context.push(path);
      },
    );
  }

  Color _categoryColor(FeedbackCategory category) {
    switch (category) {
      case FeedbackCategory.bug:
        return Colors.red;
      case FeedbackCategory.featureRequest:
        return Colors.blue;
      case FeedbackCategory.uiIssue:
        return Colors.orange;
      case FeedbackCategory.performance:
        return Colors.purple;
      case FeedbackCategory.account:
        return Colors.teal;
      case FeedbackCategory.content:
        return Colors.green;
      case FeedbackCategory.other:
        return Colors.grey;
    }
  }

  IconData _categoryIcon(FeedbackCategory category) {
    switch (category) {
      case FeedbackCategory.bug:
        return Icons.bug_report_outlined;
      case FeedbackCategory.featureRequest:
        return Icons.lightbulb_outline;
      case FeedbackCategory.uiIssue:
        return Icons.design_services_outlined;
      case FeedbackCategory.performance:
        return Icons.speed_outlined;
      case FeedbackCategory.account:
        return Icons.person_outline;
      case FeedbackCategory.content:
        return Icons.article_outlined;
      case FeedbackCategory.other:
        return Icons.help_outline;
    }
  }

  String _formatTime(int millisSinceEpoch) {
    final date = DateTime.fromMillisecondsSinceEpoch(millisSinceEpoch);
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inMinutes < 1) return 'now';
    if (diff.inHours < 1) return '${diff.inMinutes}m';
    if (diff.inDays < 1) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return '${date.month}/${date.day}';
  }
}

class _StatusBadge extends StatelessWidget {
  final FeedbackStatus status;

  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: _statusColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        status.displayName,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: _statusColor,
        ),
      ),
    );
  }

  Color get _statusColor {
    switch (status) {
      case FeedbackStatus.open:
        return Colors.blue;
      case FeedbackStatus.inProgress:
        return Colors.orange;
      case FeedbackStatus.waitingForUser:
        return Colors.amber.shade800;
      case FeedbackStatus.resolved:
        return Colors.green;
      case FeedbackStatus.closed:
        return Colors.grey;
    }
  }
}
