import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_slidable/flutter_slidable.dart';

import '../../../../core/sync/providers/sync_providers.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../domain/models/device.dart';
import '../providers/device_providers.dart';
import '../../../../shared/widgets/skeletons/skeletons.dart';

class DevicesScreen extends ConsumerWidget {
  const DevicesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devicesAsync = ref.watch(devicesListProvider);
    final currentDeviceId = ref.watch(deviceIdProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Devices'),
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
                'Failed to load devices',
                style: TextStyle(color: Colors.grey.shade600),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => ref.invalidate(devicesListProvider),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
        data: (devices) {
          final sorted = [...devices]..sort((a, b) {
              if (a.id == currentDeviceId) return -1;
              if (b.id == currentDeviceId) return 1;
              return b.lastActiveAt.compareTo(a.lastActiveAt);
            });

          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(devicesListProvider),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  '${devices.length} device${devices.length == 1 ? '' : 's'}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade600,
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
                      label: const Text('Log out all other devices'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red.shade600,
                        side: BorderSide(color: Colors.red.shade300),
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
          title: const Text('Sign Out'),
          content: const Text('This will sign you out of this device.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(
                'Sign Out',
                style: TextStyle(color: Colors.red.shade600),
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
        title: const Text('Remove Device'),
        content: Text('Remove "${device.name}" and revoke its session?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Remove',
              style: TextStyle(color: Colors.red.shade600),
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
            content: Text('Failed to remove device: $e'),
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
        title: const Text('Log Out All Other Devices'),
        content: const Text(
          'This will revoke sessions on all your other devices. '
          'They will need to log in again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Log Out Others',
              style: TextStyle(color: Colors.red.shade600),
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
            content: Text('Failed: $e'),
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
                'This device',
                style: TextStyle(
                  fontSize: 11,
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
        style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    );

    if (isCurrent) return tile;

    return Slidable(
      endActionPane: ActionPane(
        motion: const BehindMotion(),
        children: [
          SlidableAction(
            onPressed: (_) => onRemove(),
            backgroundColor: Colors.red.shade600,
            foregroundColor: Colors.white,
            icon: Icons.logout,
            label: 'Remove',
          ),
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
