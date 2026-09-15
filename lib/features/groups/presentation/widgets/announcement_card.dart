import 'package:flutter/material.dart';

import '../../../../core/sync/models/group_announcement_model.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/theme_colors.dart';
import '../../../../l10n/l10n.dart';

/// Displays a group announcement
class AnnouncementCard extends StatelessWidget {
  final GroupAnnouncementModel announcement;
  final bool canEdit;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onTogglePin;

  const AnnouncementCard({
    super.key,
    required this.announcement,
    this.canEdit = false,
    this.onEdit,
    this.onDelete,
    this.onTogglePin,
  });

  @override
  Widget build(BuildContext context) {
    final date = DateTime.fromMillisecondsSinceEpoch(announcement.createdAt);
    final timeAgo = _formatTimeAgo(date);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: announcement.pinned
            ? Border.all(
                color: AppTheme.teal.withValues(alpha: 0.3))
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (announcement.pinned) ...[
                Icon(Icons.push_pin,
                    size: 16, color: AppTheme.teal),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: Text(
                  announcement.title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (canEdit)
                PopupMenuButton<String>(
                  onSelected: (value) {
                    switch (value) {
                      case 'edit':
                        onEdit?.call();
                      case 'pin':
                        onTogglePin?.call();
                      case 'delete':
                        onDelete?.call();
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'edit',
                      child: Text(l10n(context).edit),
                    ),
                    PopupMenuItem(
                      value: 'pin',
                      child:
                          Text(announcement.pinned ? 'Unpin' : 'Pin'),
                    ),
                    const PopupMenuDivider(),
                    PopupMenuItem(
                      value: 'delete',
                      child: Text(
                        l10n(context).actionDelete,
                        style: TextStyle(color: context.dangerText),
                      ),
                    ),
                  ],
                  child: Icon(Icons.more_vert, color: context.hintText),
                ),
            ],
          ),
          if (announcement.content.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              announcement.content,
              style: TextStyle(
                fontSize: 16,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.person_outline,
                  size: 14, color: context.mutedText),
              const SizedBox(width: 4),
              Text(
                announcement.authorUsername,
                style: TextStyle(
                  fontSize: 13,
                  color: context.mutedText,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 12),
              Icon(Icons.access_time,
                  size: 14, color: context.mutedText),
              const SizedBox(width: 4),
              Text(
                timeAgo,
                style: TextStyle(
                  fontSize: 13,
                  color: context.mutedText,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatTimeAgo(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inDays > 30) {
      return '${date.month}/${date.day}/${date.year}';
    } else if (diff.inDays > 0) {
      return '${diff.inDays}d ago';
    } else if (diff.inHours > 0) {
      return '${diff.inHours}h ago';
    } else if (diff.inMinutes > 0) {
      return '${diff.inMinutes}m ago';
    } else {
      return 'Just now';
    }
  }
}
