import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/navigation/routes.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/sync/models/shared_prayer_model.dart';
import '../../../../core/sync/providers/sync_providers.dart';
import '../../../../shared/widgets/skeletons/skeletons.dart';

/// Bottom sheet for sharing a prayer with friends
class SharePrayerSheet extends ConsumerStatefulWidget {
  final String prayerId;
  final String prayerTitle;

  const SharePrayerSheet({
    super.key,
    required this.prayerId,
    required this.prayerTitle,
  });

  static Future<void> show(
    BuildContext context, {
    required String prayerId,
    required String prayerTitle,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SharePrayerSheet(
        prayerId: prayerId,
        prayerTitle: prayerTitle,
      ),
    );
  }

  @override
  ConsumerState<SharePrayerSheet> createState() => _SharePrayerSheetState();
}

class _SharePrayerSheetState extends ConsumerState<SharePrayerSheet> {
  bool _allowEditing = false;
  bool _allowLogging = true;
  bool _allowUpdates = true;
  bool _isSharing = false;

  @override
  Widget build(BuildContext context) {
    final sharedPrayerAsync =
        ref.watch(sharedPrayerProvider(widget.prayerId));

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: sharedPrayerAsync.when(
          loading: () => const SizedBox(
            height: 200,
            child: ListTileSkeletonList(count: 4),
          ),
          error: (error, _) => SizedBox(
            height: 200,
            child: Center(child: Text('Error: $error')),
          ),
          data: (shared) {
            if (shared != null) {
              return _buildSharedView(context, shared);
            }
            return _buildShareView(context);
          },
        ),
      ),
    );
  }

  Widget _buildShareView(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.share, color: AppTheme.brandBlue),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Share "${widget.prayerTitle}"',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Permissions
          const Text(
            'PERMISSIONS',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.grey,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),

          _PermissionToggle(
            title: 'Allow Editing',
            subtitle: 'Collaborators can edit the prayer text',
            value: _allowEditing,
            onChanged: (v) => setState(() => _allowEditing = v),
          ),
          _PermissionToggle(
            title: 'Allow Logging',
            subtitle: 'Collaborators can log prayer activity',
            value: _allowLogging,
            onChanged: (v) => setState(() => _allowLogging = v),
          ),
          _PermissionToggle(
            title: 'Allow Updates',
            subtitle: 'Collaborators can add prayer updates',
            value: _allowUpdates,
            onChanged: (v) => setState(() => _allowUpdates = v),
          ),
          const SizedBox(height: 24),

          // Share button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isSharing ? null : _sharePrayer,
              icon: _isSharing
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.share),
              label: const Text('Share Prayer'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.brandBlue,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSharedView(BuildContext context, SharedPrayerModel shared) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.link, color: AppTheme.brandBlue),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Prayer is Shared',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Share code
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.brandBlue.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppTheme.brandBlue.withValues(alpha: 0.2),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Share Code',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        shared.shareCode,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2,
                          color: AppTheme.brandBlue,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.copy, color: AppTheme.brandBlue),
                  onPressed: () {
                    Clipboard.setData(
                        ClipboardData(text: shared.shareCode));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Share code copied'),
                        behavior: SnackBarBehavior.floating,
                        duration: Duration(seconds: 1),
                      ),
                    );
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.share, color: AppTheme.brandBlue),
                  tooltip: 'Share link',
                  onPressed: () {
                    final link =
                        Routes.prayerDeepLink(widget.prayerId);
                    Share.share(
                      'Join me in prayer for "${widget.prayerTitle}"'
                      '\n\nCode: ${shared.shareCode}'
                      '\n$link',
                      subject: widget.prayerTitle,
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Current permissions display
          Text(
            'Permissions: '
            '${shared.allowEditing ? "Edit" : ""}'
            '${shared.allowEditing && (shared.allowLogging || shared.allowUpdates) ? ", " : ""}'
            '${shared.allowLogging ? "Log" : ""}'
            '${shared.allowLogging && shared.allowUpdates ? ", " : ""}'
            '${shared.allowUpdates ? "Updates" : ""}',
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 16),

          // Manage collaborators
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.people_outline,
                color: AppTheme.brandBlue),
            title: const Text('Manage Collaborators'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.pop(context);
              context.push(Routes.prayerCollaborators(widget.prayerId));
            },
          ),
          const Divider(),

          // Unshare button
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.link_off, color: Colors.red.shade600),
            title: Text(
              'Stop Sharing',
              style: TextStyle(color: Colors.red.shade600),
            ),
            onTap: () => _unsharePrayer(shared.id),
          ),
        ],
      ),
    );
  }

  Future<void> _sharePrayer() async {
    setState(() => _isSharing = true);

    try {
      final api = ref.read(sharedPrayerApiServiceProvider);
      await api.sharePrayer(
        prayerId: widget.prayerId,
        allowEditing: _allowEditing,
        allowLogging: _allowLogging,
        allowUpdates: _allowUpdates,
      );

      ref.invalidate(sharedPrayerProvider(widget.prayerId));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Prayer shared!'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to share: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }

    if (mounted) {
      setState(() => _isSharing = false);
    }
  }

  Future<void> _unsharePrayer(String sharedPrayerId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Stop Sharing'),
        content: const Text(
          'This will remove access for all collaborators. Are you sure?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Stop Sharing'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final api = ref.read(sharedPrayerApiServiceProvider);
      await api.unsharePrayer(widget.prayerId);
      ref.invalidate(sharedPrayerProvider(widget.prayerId));

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Prayer is no longer shared'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to unshare: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }
}

class _PermissionToggle extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _PermissionToggle({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title, style: const TextStyle(fontSize: 14)),
      subtitle: Text(
        subtitle,
        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
      ),
      value: value,
      onChanged: onChanged,
      activeTrackColor: AppTheme.brandBlue.withValues(alpha: 0.5),
    );
  }
}
