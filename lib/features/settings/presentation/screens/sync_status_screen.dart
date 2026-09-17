import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/database/sync_database.dart';
import '../../../../core/sync/engine/sync_state_machine.dart';
import '../../../../core/sync/providers/sync_providers.dart';
import '../../../../core/services/user_facing_error.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/theme_colors.dart';
import '../../../../core/sync/models/stalled_change.dart';
import '../../../../l10n/l10n.dart';

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

/// Built per-call rather than as a const list: the labels are localised, and
/// a const list cannot hold a lookup. Cheap — it is read once per build of
/// the sync screen.
List<_EntityCategory> _entityCategories(AppLocalizations s) => [
  _EntityCategory(
    label: s.navNotes,
    icon: Icons.note_alt_outlined,
    keys: ['note', 'note_block', 'folder'],
  ),
  _EntityCategory(
    label: s.navPrayers,
    icon: Icons.volunteer_activism_outlined,
    keys: [
      'prayer',
      'prayer_log',
      'prayer_update',
      'prayer_tag',
      'prayer_person',
      'prayer_collaborator',
      'shared_prayer',
    ],
  ),
  _EntityCategory(
    label: s.navPromises,
    icon: Icons.workspace_premium_outlined,
    keys: [
      'promise',
      'promise_condition',
      'promise_tag',
      'promise_prayer_link',
    ],
  ),
  _EntityCategory(
    label: s.people,
    icon: Icons.people_outline,
    keys: ['person'],
  ),
  _EntityCategory(
    label: s.navSongs,
    icon: Icons.music_note_outlined,
    keys: ['song', 'song_tag', 'preacher'],
  ),
  _EntityCategory(
    label: s.groups,
    icon: Icons.group_outlined,
    keys: [
      'group',
      'group_member',
      'group_prayer',
      'group_announcement',
      'pending_group_member',
    ],
  ),
  _EntityCategory(
    label: s.friends,
    icon: Icons.person_add_outlined,
    keys: ['friendship', 'friend_request', 'blocked_user'],
  ),
  _EntityCategory(
    label: s.tags,
    icon: Icons.label_outline,
    keys: ['tag', 'note_tag'],
  ),
  _EntityCategory(
    label: s.navBible,
    icon: Icons.menu_book_outlined,
    keys: ['bible_highlight', 'bible_reference_history'],
  ),
  _EntityCategory(
    label: s.habits,
    icon: Icons.check_circle_outline,
    keys: ['habit_log'],
  ),
  _EntityCategory(
    label: s.profile,
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
        title: Text(l10n(context).syncStatus),
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

          // Anything sync gave up on. Hidden entirely when there is nothing,
          // so it is a signal rather than permanent furniture.
          ref
              .watch(stalledChangesProvider)
              .maybeWhen(
                data: (changes) => changes.isEmpty
                    ? const SizedBox.shrink()
                    : Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: _buildStalledChanges(context, ref, changes),
                      ),
                orElse: () => const SizedBox.shrink(),
              ),

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
                  Icon(
                    Icons.pending_actions,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n(context).pendingOperations,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        pendingOps.when(
                          data: (count) => Text(
                            '$count operations waiting to sync',
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                          ),
                          loading: () => Text(
                            l10n(context).loading,
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                          ),
                          error: (_, _) => Text(
                            l10n(context).unableToFetch,
                            style: TextStyle(color: context.dangerText),
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
              label: Text(
                l10n(context).syncNow,
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
              label: Text(
                l10n(context).forceFullReSync,
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
      SyncEngineState.idle when progress.hasPendingOps => (
        Icons.pending_outlined,
        Colors.orange,
        'Pending',
      ),
      SyncEngineState.idle => (Icons.cloud_done, Colors.green, 'Synced'),
      SyncEngineState.pushing => (
        Icons.cloud_upload,
        Colors.blue,
        'Pushing changes...',
      ),
      SyncEngineState.pulling => (
        Icons.cloud_download,
        Colors.blue,
        'Pulling changes...',
      ),
      SyncEngineState.applying => (
        Icons.sync,
        Colors.blue,
        'Applying changes...',
      ),
      SyncEngineState.error => (Icons.cloud_off, Colors.red, 'Sync error'),
      SyncEngineState.offline => (Icons.cloud_off, Colors.grey, 'Offline'),
      SyncEngineState.paused => (
        Icons.pause_circle_outline,
        Colors.orange,
        'Paused',
      ),
      SyncEngineState.degraded => (
        Icons.warning_amber,
        Colors.deepOrange,
        'Sync degraded',
      ),
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
                fontSize: 14,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
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
        label: l10n(context).lastSuccessfulPush,
        value: _formatRelative(state.lastPushTimestamp),
      ),
      _DiagRow(
        icon: Icons.cloud_download_outlined,
        label: l10n(context).lastSuccessfulPull,
        value: _formatRelative(state.lastPullTimestamp),
      ),
      _DiagRow(
        icon: Icons.schedule_outlined,
        label: l10n(context).lastSyncAttempt,
        value: _formatRelative(state.lastSyncAttempt),
      ),
      _DiagRow(
        icon: Icons.numbers_outlined,
        label: l10n(context).consecutiveFailures,
        value: '${state.consecutiveFailures}',
        valueColor: state.consecutiveFailures > 0
            ? theme.colorScheme.error
            : null,
      ),
      _DiagRow(
        icon: Icons.linear_scale,
        label: l10n(context).remoteCursor,
        value: state.lastRemoteCursor == null
            ? 'none (next pull is a snapshot)'
            : _truncate(state.lastRemoteCursor!, 40),
        monospace: true,
      ),
      if (state.lastError != null && state.lastError!.isNotEmpty)
        _DiagRow(
          icon: Icons.error_outline,
          label: l10n(context).lastError,
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
            Padding(
              padding: EdgeInsets.fromLTRB(20, 12, 20, 4),
              child: Text(
                l10n(context).diagnostics,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
            ...rows,
          ],
        ),
      ),
    );
  }

  Widget _buildStalledChanges(
    BuildContext context,
    WidgetRef ref,
    List<StalledChange> changes,
  ) {
    final theme = Theme.of(context);
    final hasIncoming = changes.any(
      (c) => c.direction == StalledDirection.incoming,
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.cardSurface,
        borderRadius: AppTheme.borderRadius2XL,
        border: Border.all(
          color: theme.colorScheme.error.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.report_gmailerrorred_outlined,
                size: 20,
                color: theme.colorScheme.error,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n(context).changesNeedingAttention,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            l10n(context).stalledChangesExplanation,
            style: theme.textTheme.bodySmall?.copyWith(
              color: context.mutedText,
            ),
          ),
          const SizedBox(height: 12),
          ...changes.map((c) => _buildStalledRow(context, c)),
          const SizedBox(height: 4),
          if (hasIncoming) ...[
            Text(
              l10n(context).retryFullRecheckNote,
              style: theme.textTheme.bodySmall?.copyWith(
                color: context.mutedText,
                fontStyle: FontStyle.italic,
              ),
            ),
            const SizedBox(height: 8),
          ],
          const Align(
            alignment: Alignment.centerRight,
            child: _RetryStalledButton(),
          ),
        ],
      ),
    );
  }

  Widget _buildStalledRow(BuildContext context, StalledChange change) {
    final theme = Theme.of(context);
    final isOutgoing = change.direction == StalledDirection.outgoing;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isOutgoing
                    ? Icons.cloud_upload_outlined
                    : Icons.cloud_download_outlined,
                size: 14,
                color: context.mutedText,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${change.entityType} · ${change.entityId}',
                  style: theme.textTheme.bodySmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                isOutgoing
                    ? l10n(context).stalledOutgoing
                    : l10n(context).stalledIncoming,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: context.mutedText,
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 20, top: 2),
            child: Text(
              change.reason,
              style: theme.textTheme.bodySmall?.copyWith(
                color: context.mutedText,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(BuildContext context) {
    return Column(
      children: [
        Icon(Icons.error_outline, size: 48, color: context.dangerText),
        const SizedBox(height: 12),
        Text(
          l10n(context).unableToConnectToSyncService,
          style: TextStyle(fontSize: 16, color: context.dangerText),
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
        ? _entityCategories(
            l10n(context),
          ).where((c) => c.countFrom(counts) > 0).toList()
        : _entityCategories(l10n(context));

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
                l10n(context).data,
                style: const TextStyle(
                  fontSize: 16,
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
        Text(label, style: TextStyle(color: color, fontSize: 14)),
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
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            )
          : const SizedBox.shrink();
    } else {
      trailing = switch (progress.state) {
        SyncEngineState.error => _buildStatusBadge(
          Icons.error_outline,
          Colors.red.shade400,
          'Error',
        ),
        SyncEngineState.degraded => _buildStatusBadge(
          Icons.warning_amber,
          Colors.deepOrange.shade400,
          'Degraded',
        ),
        SyncEngineState.paused => _buildStatusBadge(
          Icons.pause_circle_outline,
          Colors.orange.shade600,
          'Paused',
        ),
        _ => _buildStatusBadge(
          Icons.check_circle_outline,
          Colors.green.shade600,
          'Synced',
        ),
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
      title: Text(cat.label, style: const TextStyle(fontSize: 16)),
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
              content: Text(
                l10n(
                  context,
                ).fullResyncFailed(result.error ?? l10n(context).unknownError),
              ),
              behavior: SnackBarBehavior.floating,
              backgroundColor: AppTheme.errorSurface,
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              UserFacingError.message(e, action: 're-sync your data'),
            ),
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppTheme.errorSurface,
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
              content: Text(
                l10n(context).syncFailedWithError(
                  result.error ?? l10n(context).unknownError,
                ),
              ),
              behavior: SnackBarBehavior.floating,
              backgroundColor: AppTheme.errorSurface,
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(UserFacingError.message(e, action: 'sync your data')),
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppTheme.errorSurface,
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
          Icon(Icons.warning_amber, color: context.warningText),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n(context).syncDegraded,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: context.warningText,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  l10n(context).tooManyConsecutiveFailuresAutomatedSyncsAre,
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
          Icon(
            icon,
            size: 18,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
          ),
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

/// The retry control, kept as its own widget so the screen can stay a
/// ConsumerWidget: the only state here is whether a retry is in flight.
class _RetryStalledButton extends ConsumerStatefulWidget {
  const _RetryStalledButton();

  @override
  ConsumerState<_RetryStalledButton> createState() =>
      _RetryStalledButtonState();
}

class _RetryStalledButtonState extends ConsumerState<_RetryStalledButton> {
  bool _retrying = false;

  Future<void> _retry() async {
    setState(() => _retrying = true);
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(content: Text(l10n(context).retryingChanges)),
    );
    try {
      await retryStalledChanges(ref);
    } finally {
      if (mounted) setState(() => _retrying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FilledButton.tonalIcon(
      onPressed: _retrying ? null : _retry,
      icon: _retrying
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.refresh, size: 18),
      label: Text(l10n(context).tryAgain),
    );
  }
}
