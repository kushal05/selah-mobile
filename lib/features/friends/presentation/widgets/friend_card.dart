import 'package:flutter/material.dart';

import '../../../../core/sync/models/friendship_model.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/theme_colors.dart';
import '../../../../l10n/l10n.dart';

/// Displays a friend in the friends list
class FriendCard extends StatelessWidget {
  final FriendshipModel friendship;
  final VoidCallback? onTap;
  final VoidCallback? onRemove;

  const FriendCard({
    super.key,
    required this.friendship,
    this.onTap,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final initials = friendship.initials;
    final displayName = friendship.friendDisplayName.isNotEmpty
        ? friendship.friendDisplayName
        : friendship.friendUsername;

    return InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor:
                  AppTheme.teal.withValues(alpha: 0.1),
              child: Text(
                initials,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.teal,
                ),
              ),
            ),
            const SizedBox(width: 16),
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
                  const SizedBox(height: 4),
                  Text(
                    '@${friendship.friendUsername}',
                    style: TextStyle(
                      fontSize: 16,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (onRemove != null)
              IconButton(
                tooltip: l10n(context).friendOptions,
                icon: Icon(Icons.more_vert, color: context.hintText),
                onPressed: () => _showOptions(context),
              )
            else
              Icon(Icons.chevron_right, color: context.hintText),
          ],
        ),
      ),
    );
  }

  void _showOptions(BuildContext context) {
    showModalBottomSheet(
      // Defaults to false: a scroll-controlled sheet otherwise draws its
      // top edge behind the notch or Dynamic Island.
      useSafeArea: true,
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.person_remove, color: context.dangerText),
              title: Text(
                l10n(context).removeFriend,
                style: TextStyle(color: context.dangerText),
              ),
              onTap: () {
                Navigator.pop(context);
                onRemove?.call();
              },
            ),
          ],
        ),
      ),
    );
  }
}
