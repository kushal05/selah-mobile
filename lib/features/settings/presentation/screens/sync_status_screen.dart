import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/database/sync_database.dart';
import '../../../../core/sync/engine/sync_state_machine.dart';
import '../../../../core/sync/providers/sync_providers.dart';

/// Loads the persisted sync state row (last push/pull, cursor, last error,
/// consecutive failures) for the diagnostics card. Refetched whenever the
/// screen invalidates it after a manual sync.
final syncDiagnosticsProvider = FutureProvider<SyncStateData>((ref) async {
  final db = ref.watch(syncDatabaseProvider);
  return db.getSyncState();
});

class _EntityCategory {
  final String label;
  final IconData icon;
  final List<String> keys;
  const _EntityCategory({
    required this.label,
    required this.icon,
    required this.keys,
  });

  int countFrom(Map<String, int> counts) =>
      keys.fold(0, (sum, k) => sum + (counts[k] ?? 0));
}

const _entityCategories = [
  _EntityCategory(
    label: 'Notes',
    icon: Icons.note_alt_outlined,
    keys: ['note', 'note_block', 'folder'],
  ),
  _EntityCategory(
    label: 'Prayers',
    icon: Icons.volunteer_activism_outlined,
    keys: [
      'prayer', 'prayer_log', 'prayer_update', 'prayer_tag',
      'prayer_person', 'prayer_collaborator', 'shared_prayer',
    ],
  ),
  _EntityCategory(
    label: 'Promises',
    icon: Icons.workspace_premium_outlined,
    keys: ['promise', 'promise_condition', 'promise_tag', 'promise_prayer_link'],
  ),
  _EntityCategory(
    label: 'People',
    icon: Icons.people_outline,
    keys: ['person'],
  ),
  _EntityCategory(
    label: 'Songs',
    icon: Icons.music_note_outlined,
    keys: ['song', 'song_tag', 'preacher'],
  ),
  _EntityCategory(
    label: 'Groups',
    icon: Icons.group_outlined,
    keys: [
      'group', 'group_member', 'group_prayer',
      'group_announcement', 'pending_group_member',
    ],
  ),
  _EntityCategory(
    label: 'Friends',
    icon: Icons.person_add_outlined,
    keys: ['friendship', 'friend_request', 'blocked_user'],
  ),
  _EntityCategory(
    label: 'Tags',
    icon: Icons.label_outline,
    keys: ['tag', 'note_tag'],
  ),
  _EntityCategory(
    label: 'Bible',
    icon: Icons.menu_book_outlined,
    keys: ['bible_highlight', 'bible_reference_history'],
  ),
  _EntityCategory(
    label: 'Habits',
    icon: Icons.check_circle_outline,
    keys: ['habit_log'],
  ),
  _EntityCategory(
    label: 'Profile',
    icon: Icons.account_circle_outlined,
    keys: ['user_profile'],
  ),
];

/// Sync status screen showing detailed sync information
class SyncStatusScreen extends ConsumerWidget {
  const SyncStatusScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final syncProgress = ref.watch(syncProgressProvider);
    final pendingOps = ref.watch(pendingOpsCountProvider);
    final diagnostics = ref.watch(syncDiagnosticsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sync Status'),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Degraded banner — only when the engine has given up on automated
          // retries and is waiting for the user to take action.
          if (syncProgress.valueOrNull?.state == SyncEngineState.degraded) ...[
            _DegradedBanner(),
            const SizedBox(height: 16),
          ],

          // Sync state card
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: syncProgress.when(
                data: (progress) => _buildSyncState(context, progress),
                loading: () => _buildSyncState(
                  context,
                  const SyncProgress(
                    state: SyncEngineState.idle,
                    pendingOps: 0,
                    totalOps: 0,
                    percentage: 0,
                  ),
                ),
                error: (_, _) => _buildErrorState(context),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Diagnostics card — last push/pull, cursor, last error, failures.
          diagnostics.when(
            data: (state) => _buildDiagnostics(context, state),
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
          ),
          const SizedBox(height: 16),

          // Entity breakdown card
          syncProgress.when(
            data: (progress) => _buildEntityBreakdown(context, progress),
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
          ),
          const SizedBox(height: 16),

          // Pending operations card
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Icon(Icons.pending_actions,
                      color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Pending Operations',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        pendingOps.when(
                          data: (count) => Text(
                            '$count operations waiting to sync',
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                          loading: () => Text(
                            'Loading...',
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                          error: (_, _) => Text(
                            'Unable to fetch',
                            style: TextStyle(color: Colors.red.shade600),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Sync now button
          SizedBox(
            height: 52,
            child: ElevatedButton.icon(
              onPressed: () => _triggerSync(context, ref),
              icon: const Icon(Icons.sync),
              label: const Text(
                'Sync Now',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Force full re-sync button (resets cursor → triggers snapshot pull)
          SizedBox(
            height: 52,
            child: OutlinedButton.icon(
              onPressed: () => _triggerFullSync(context, ref),
              icon: const Icon(Icons.refresh),
              label: const Text(
                'Force Full Re-Sync',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSyncState(BuildContext context, SyncProgress progress) {
    final (icon, color, label) = switch (progress.state) {
      SyncEngineState.idle when progress.hasPendingOps =>
        (Icons.pending_outlined, Colors.orange, 'Pending'),
      SyncEngineState.idle => (Icons.cloud_done, Colors.green, 'Synced'),
      SyncEngineState.pushing => (Icons.cloud_upload, Colors.blue, 'Pushing changes...'),
      SyncEngineState.pulling => (Icons.cloud_download, Colors.blue, 'Pulling changes...'),
      SyncEngineState.applying => (Icons.sync, Colors.blue, 'Applying changes...'),
      SyncEngineState.error => (Icons.cloud_off, Colors.red, 'Sync error'),
      SyncEngineState.offline => (Icons.cloud_off, Colors.grey, 'Offline'),
      SyncEngineState.paused => (Icons.pause_circle_outline, Colors.orange, 'Paused'),
      SyncEngineState.degraded =>
        (Icons.warning_amber, Colors.deepOrange, 'Sync degraded'),
    };

    return Column(
      children: [
        Icon(icon, size: 48, color: color),
        const SizedBox(height: 12),
        Text(
          label,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
        if (progress.isSyncing) ...[
          const SizedBox(height: 16),
          LinearProgressIndicator(
            value: progress.percentage > 0 ? progress.percentage : null,
            borderRadius: BorderRadius.circular(4),
          ),
          if (progress.currentEntity != null) ...[
            const SizedBox(height: 8),
            Text(
              'Syncing: ${progress.currentEntity}',
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ],
      ],
    );
  }

  Widget _buildDiagnostics(BuildContext context, SyncStateData state) {
    final theme = Theme.of(context);
    final rows = <Widget>[
      _DiagRow(
        icon: Icons.cloud_upload_outlined,
        label: 'Last successful push',
        value: _formatRelative(state.lastPushTimestamp),
      ),
      _DiagRow(
        icon: Icons.cloud_download_outlined,
        label: 'Last successful pull',
        value: _formatRelative(state.lastPullTimestamp),
      ),
      _DiagRow(
        icon: Icons.schedule_outlined,
        label: 'Last sync attempt',
        value: _formatRelative(state.lastSyncAttempt),
      ),
      _DiagRow(
        icon: Icons.numbers_outlined,
        label: 'Consecutive failures',
        value: '${state.consecutiveFailures}',
        valueColor: state.consecutiveFailures > 0
            ? theme.colorScheme.error
            : null,
      ),
      _DiagRow(
        icon: Icons.linear_scale,
        label: 'Remote cursor',
        value: state.lastRemoteCursor == null
            ? 'none (next pull is a snapshot)'
            : _truncate(state.lastRemoteCursor!, 40),
        monospace: true,
      ),
      if (state.lastError != null && state.lastError!.isNotEmpty)
        _DiagRow(
          icon: Icons.error_outline,
          label: 'Last error',
          value: state.lastError!,
          valueColor: theme.colorScheme.error,
          maxLines: 3,
        ),
    ];

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 12, 20, 4),
              child: Text(
                'Diagnostics',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
            ...rows,
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(BuildContext context) {
    return Column(
      children: [
        Icon(Icons.error_outline, size: 48, color: Colors.red.shade400),
        const SizedBox(height: 12),
        Text(
          'Unable to connect to sync service',
          style: TextStyle(
            fontSize: 16,
            color: Colors.red.shade600,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildEntityBreakdown(BuildContext context, SyncProgress progress) {
    final isSyncing = progress.isSyncing;
    final counts = progress.entityCounts;

    // During sync: show only categories with activity (rows appear as data arrives).
    // When not syncing: show all categories with a state-appropriate badge.
    final visibleCategories = isSyncing
        ? _entityCategories.where((c) => c.countFrom(counts) > 0).toList()
        : _entityCategories;

    if (visibleCategories.isEmpty) return const SizedBox.shrink();

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
              child: Text(
                'Data',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            ...visibleCategories.map(
              (cat) => _buildEntityRow(context, cat, counts, progress),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge(IconData icon, Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(color: color, fontSize: 13)),
      ],
    );
  }

  Widget _buildEntityRow(
    BuildContext context,
    _EntityCategory cat,
    Map<String, int> counts,
    SyncProgress progress,
  ) {
    final count = cat.countFrom(counts);
    Widget trailing;
    if (progress.isSyncing) {
      trailing = count > 0
          ? Text(
              '$count',
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            )
          : const SizedBox.shrink();
    } else {
      trailing = switch (progress.state) {
        SyncEngineState.error =>
          _buildStatusBadge(Icons.error_outline, Colors.red.shade400, 'Error'),
        SyncEngineState.degraded =>
          _buildStatusBadge(Icons.warning_amber, Colors.deepOrange.shade400, 'Degraded'),
        SyncEngineState.paused =>
          _buildStatusBadge(Icons.pause_circle_outline, Colors.orange.shade600, 'Paused'),
        _ =>
          _buildStatusBadge(Icons.check_circle_outline, Colors.green.shade600, 'Synced'),
      };
    }

    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      leading: Icon(
        cat.icon,
        size: 20,
        color: progress.isSyncing && count > 0
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
      ),
      title: Text(cat.label, style: const TextStyle(fontSize: 14)),
      trailing: trailing,
    );
  }

  Future<void> _triggerFullSync(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(syncInitializedProvider.future);
      final syncService = await ref.read(syncServiceProvider.future);
      final result = await syncService.resetAndSync();
      if (context.mounted) {
        if (result.success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Full re-sync complete — pushed ${result.operationsPushed}, '
                'pulled ${result.operationsPulled}',
              ),
              behavior: SnackBarBehavior.floating,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Full re-sync failed: ${result.error ?? "Unknown error"}'),
              behavior: SnackBarBehavior.floating,
              backgroundColor: Colors.red.shade600,
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Full re-sync failed: $e'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.red.shade600,
          ),
        );
      }
    }
  }

  Future<void> _triggerSync(BuildContext context, WidgetRef ref) async {
    try {
      // Ensure sync service is initialized before calling syncNow
      await ref.read(syncInitializedProvider.future);
      final syncService = await ref.read(syncServiceProvider.future);
      final result = await syncService.syncNow();
      // Reload the persisted diagnostics row so timestamps, cursor, and
      // failure count reflect the attempt we just made.
      ref.invalidate(syncDiagnosticsProvider);
      if (context.mounted) {
        if (result.success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Sync complete — pushed ${result.operationsPushed}, '
                'pulled ${result.operationsPulled}',
              ),
              behavior: SnackBarBehavior.floating,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Sync failed: ${result.error ?? "Unknown error"}'),
              behavior: SnackBarBehavior.floating,
              backgroundColor: Colors.red.shade600,
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sync failed: $e'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.red.shade600,
          ),
        );
      }
    }
  }
}

String _formatRelative(int? timestampMs) {
  if (timestampMs == null || timestampMs <= 0) return 'never';
  final now = DateTime.now().millisecondsSinceEpoch;
  final diff = now - timestampMs;
  if (diff < 0) return 'just now';
  if (diff < 60 * 1000) return 'just now';
  if (diff < 60 * 60 * 1000) return '${diff ~/ 60000}m ago';
  if (diff < 24 * 60 * 60 * 1000) return '${diff ~/ 3600000}h ago';
  if (diff < 7 * 24 * 60 * 60 * 1000) return '${diff ~/ 86400000}d ago';
  final dt = DateTime.fromMillisecondsSinceEpoch(timestampMs);
  return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
}

String _truncate(String s, int maxLen) =>
    s.length <= maxLen ? s : '${s.substring(0, maxLen)}…';

class _DegradedBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.deepOrange.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.deepOrange.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber, color: Colors.deepOrange),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Sync degraded',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: Colors.deepOrange.shade700,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Too many consecutive failures — automated syncs are paused. '
                  'Tap "Sync Now" below to try again.',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DiagRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;
  final bool monospace;
  final int maxLines;

  const _DiagRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
    this.monospace = false,
    this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: theme.textTheme.bodySmall),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: maxLines,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: valueColor,
                    fontFamily: monospace ? 'monospace' : null,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
