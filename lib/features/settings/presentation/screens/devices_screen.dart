import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_slidable/flutter_slidable.dart';

import '../../../../core/sync/providers/sync_providers.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../domain/models/device.dart';
import '../providers/device_providers.dart';
import '../../../../shared/widgets/skeletons/skeletons.dart';
import '../../../../core/services/user_facing_error.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/theme_colors.dart';
import '../../../../l10n/l10n.dart';
import '../../../../shared/widgets/swipe_action.dart';

class DevicesScreen extends ConsumerWidget {
  const DevicesScreen({super.key});

  /// This device first, then most recently active.
  ///
  /// Hoisted out of build: it copied and sorted the list on every rebuild,
  /// including every frame of the refresh indicator's animation.
  static List<Device> _sortedByRecency(
      List<Device> devices, String? currentDeviceId) {
    return [...devices]..sort((a, b) {
        if (a.id == currentDeviceId) return -1;
        if (b.id == currentDeviceId) return 1;
        return b.lastActiveAt.compareTo(a.lastActiveAt);
      });
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devicesAsync = ref.watch(devicesListProvider);
    final currentDeviceId = ref.watch(deviceIdProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n(context).devices),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
      ),
      body: devicesAsync.when(
        loading: () => const ListTileSkeletonList(count: 4, hasLeading: false),
        error: (error, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l10n(context).failedToLoadDevices,
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => ref.invalidate(devicesListProvider),
                child: Text(l10n(context).retry),
              ),
            ],
          ),
        ),
        data: (devices) {
          final sorted = _sortedByRecency(devices, currentDeviceId);

          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(devicesListProvider),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  '${devices.length} device${devices.length == 1 ? '' : 's'}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 12),
                ...sorted.map(
                  (device) => _DeviceTile(
                    device: device,
                    isCurrent: device.id == currentDeviceId,
                    onRemove: () => _removeDevice(context, ref, device),
                  ),
                ),
                if (devices.length > 1) ...[
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () =>
                          _revokeOtherDevices(context, ref, currentDeviceId),
                      icon: const Icon(Icons.logout),
                      label: Text(l10n(context).logOutAllOtherDevices),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: context.dangerText,
                        side: BorderSide(color: context.dangerText),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 32),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _removeDevice(
    BuildContext context,
    WidgetRef ref,
    Device device,
  ) async {
    final currentDeviceId = ref.read(deviceIdProvider);

    if (device.id == currentDeviceId) {
      // Removing current device = sign out
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l10n(context).signOut),
          content: Text(l10n(context).thisWillSignYouOutOfThisDevice),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l10n(context).actionCancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(
                l10n(context).signOut,
                style: TextStyle(color: context.dangerText),
              ),
            ),
          ],
        ),
      );
      if (confirmed == true) {
        await ref.read(authNotifierProvider.notifier).logout();
      }
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n(context).removeDevice),
        content: Text(l10n(context).removeDeviceAndRevokeSession(device.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n(context).actionCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              l10n(context).remove,
              style: TextStyle(color: context.dangerText),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    try {
      final api = ref.read(deviceApiServiceProvider);
      await api.removeDevice(device.id);
      ref.invalidate(devicesListProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('"${device.name}" removed'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(UserFacingError.message(e, action: 'remove device')),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _revokeOtherDevices(
    BuildContext context,
    WidgetRef ref,
    String currentDeviceId,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n(context).logOutAllOtherDevices),
        content: Text(
          l10n(context).thisWillRevokeSessionsOnAllYourOtherDevicesT,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n(context).actionCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              l10n(context).logOutOthers,
              style: TextStyle(color: context.dangerText),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    try {
      final api = ref.read(deviceApiServiceProvider);
      final count = await api.revokeOtherDevices(currentDeviceId);
      ref.invalidate(devicesListProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text('$count device${count == 1 ? '' : 's'} logged out'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(UserFacingError.message(e, action: 'do that')),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }
}

class _DeviceTile extends StatelessWidget {
  final Device device;
  final bool isCurrent;
  final VoidCallback onRemove;

  const _DeviceTile({
    required this.device,
    required this.isCurrent,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final tile = ListTile(
      leading: Icon(_platformIcon(device.platform), size: 28),
      title: Row(
        children: [
          Flexible(
            child: Text(device.name, overflow: TextOverflow.ellipsis),
          ),
          if (isCurrent) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .primary
                    .withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                l10n(context).thisDevice,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
          ],
        ],
      ),
      subtitle: Text(
        '${device.platform} \u00B7 Active ${_formatLastActive(device.lastActiveAt)}',
        style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    );

    if (isCurrent) return tile;

    return Slidable(
      endActionPane: ActionPane(
        motion: const BehindMotion(),
        children: [
          buildSwipeAction(
            icon: Icons.logout,
            label: l10n(context).remove,
            accent: AppTheme.error,
            onPressed: (_) => onRemove(),
          )
        ],
      ),
      child: tile,
    );
  }

  IconData _platformIcon(String platform) {
    switch (platform.toLowerCase()) {
      case 'android':
        return Icons.phone_android;
      case 'ios':
        return Icons.phone_iphone;
      case 'windows':
        return Icons.laptop_windows;
      case 'macos':
        return Icons.laptop_mac;
      case 'linux':
        return Icons.computer;
      case 'web':
        return Icons.language;
      default:
        return Icons.devices;
    }
  }

  String _formatLastActive(DateTime lastActive) {
    final diff = DateTime.now().difference(lastActive);
    if (diff.inMinutes < 2) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 30) return '${diff.inDays}d ago';
    return '${(diff.inDays / 30).round()}mo ago';
  }
}
