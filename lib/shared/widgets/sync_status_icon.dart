import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/navigation/routes.dart';
import '../../core/sync/engine/sync_state_machine.dart';
import '../../core/sync/providers/sync_providers.dart';
import 'skeletons/skeletons.dart';

/// Small sync status icon that shows current sync state
class SyncStatusIcon extends ConsumerWidget {
  const SyncStatusIcon({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Only rebuild when the sync state enum changes, not on every progress emission
    final syncState = ref.watch(syncProgressProvider.select(
      (async) => async.whenData((p) => p.state),
    ));

    return syncState.when(
      data: (state) => _buildIconFromState(context, state),
      loading: () => const BaseSkeleton(width: 20, height: 20, borderRadius: 10),
      error: (_, _) => IconButton(
        icon: Icon(Icons.cloud_off, color: Colors.red.shade400, size: 20),
        onPressed: () => context.push(Routes.syncStatus),
        tooltip: 'Sync error',
      ),
    );
  }

  Widget _buildIconFromState(BuildContext context, SyncEngineState state) {
    final (icon, color) = switch (state) {
      SyncEngineState.idle => (Icons.cloud_done_outlined, Colors.green),
      SyncEngineState.pushing ||
      SyncEngineState.pulling ||
      SyncEngineState.applying => (Icons.sync, Colors.blue),
      SyncEngineState.error => (Icons.cloud_off, Colors.red),
      SyncEngineState.offline => (Icons.cloud_off_outlined, Colors.grey),
      SyncEngineState.paused => (Icons.pause_circle_outline, Colors.orange),
      SyncEngineState.degraded =>
        (Icons.warning_amber, Colors.deepOrange),
    };

    final isSyncing = state == SyncEngineState.pushing ||
        state == SyncEngineState.pulling ||
        state == SyncEngineState.applying;

    Widget iconWidget = Icon(icon, color: color, size: 20);

    if (isSyncing) {
      iconWidget = _RotatingIcon(icon: icon, color: color);
    }

    return IconButton(
      icon: iconWidget,
      onPressed: () => context.push(Routes.syncStatus),
      tooltip: 'Sync status',
    );
  }
}

class _RotatingIcon extends StatefulWidget {
  final IconData icon;
  final Color color;

  const _RotatingIcon({required this.icon, required this.color});

  @override
  State<_RotatingIcon> createState() => _RotatingIconState();
}

class _RotatingIconState extends State<_RotatingIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 1),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: _controller,
      child: Icon(widget.icon, color: widget.color, size: 20),
    );
  }
}
