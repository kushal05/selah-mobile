import 'package:flutter/material.dart';

import '../../../../core/sync/models/friend_request_model.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/theme_colors.dart';
import '../../../../l10n/l10n.dart';

/// Displays a friend request with accept/reject actions
class FriendRequestCard extends StatelessWidget {
  final FriendRequestModel request;
  final bool isIncoming;
  final VoidCallback? onAccept;
  final VoidCallback? onReject;
  final VoidCallback? onCancel;

  const FriendRequestCard({
    super.key,
    required this.request,
    required this.isIncoming,
    this.onAccept,
    this.onReject,
    this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final name = isIncoming ? request.fromUsername : request.toUsername;
    final displayName = isIncoming
        ? (request.fromDisplayName.isNotEmpty
            ? request.fromDisplayName
            : request.fromUsername)
        : (request.toDisplayName.isNotEmpty
            ? request.toDisplayName
            : request.toUsername);
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Row(
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
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '@$name',
                      style: TextStyle(
                        fontSize: 14,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (!isIncoming)
                Text(
                  l10n(context).pending,
                  style: TextStyle(
                    fontSize: 13,
                    color: context.warningText,
                    fontWeight: FontWeight.w500,
                  ),
                ),
            ],
          ),
          if (isIncoming) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: onReject,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: context.mutedText,
                      side: BorderSide(color: context.mutedText),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Text(l10n(context).decline),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: onAccept,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.teal,
                      foregroundColor: AppTheme.onAccent(AppTheme.teal),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Text(l10n(context).accept),
                  ),
                ),
              ],
            ),
          ] else ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: onCancel,
                style: OutlinedButton.styleFrom(
                  foregroundColor: context.dangerText,
                  side: BorderSide(color: context.dangerText),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: Text(l10n(context).cancelRequest),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
