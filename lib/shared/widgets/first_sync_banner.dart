import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/motion_preferences.dart';
import '../../core/sync/engine/sync_state_machine.dart';
import '../../core/sync/providers/sync_providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/theme_colors.dart';
import '../../l10n/l10n.dart';

/// Whether this account has ever finished pulling from the server.
///
/// Null `lastPullTimestamp` means the first sync has not completed, which is
/// the difference between "you have no notes" and "your notes have not arrived
/// yet" — indistinguishable on screen otherwise, and the second one is what a
/// user reads as data loss.
final hasCompletedFirstSyncProvider = FutureProvider<bool>((ref) async {
  final db = ref.watch(syncDatabaseProvider);
  final state = await db.getSyncState();
  return state.lastPullTimestamp != null;
});

/// Explains an empty app on a freshly signed-in device.
///
/// Sync was previously invisible in normal operation: the only always-on
/// indicators were the offline banner and the degraded banner, and the latter
/// needs ten consecutive failures — over two hours at the retry cadence. In
/// between, a first pull that was still running, or had failed once, showed
/// nothing at all. A new user saw an empty app and no reason for it.
///
/// This covers only that window. Once the first pull has landed the banner
/// disappears for good, so it cannot become background noise for an
/// established user; ongoing trouble is the degraded banner's job.
class FirstSyncBanner extends ConsumerWidget {
  const FirstSyncBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasSynced =
        ref.watch(hasCompletedFirstSyncProvider).valueOrNull ?? true;

    // Nothing to explain once the account has its data.
    if (hasSynced) return const SizedBox.shrink();

    final state = ref
        .watch(syncProgressProvider.select((a) => a.whenData((p) => p.state)))
        .valueOrNull;

    final isWorking =
        state == SyncEngineState.pulling ||
        state == SyncEngineState.applying ||
        state == SyncEngineState.pushing;
    final hasFailed =
        state == SyncEngineState.error || state == SyncEngineState.degraded;

    // Offline already has its own banner saying so; two stacked bars saying
    // overlapping things is worse than one.
    if (state == SyncEngineState.offline) return const SizedBox.shrink();
    if (!isWorking && !hasFailed) return const SizedBox.shrink();

    return AnimatedSize(
      duration: context.motion(const Duration(milliseconds: 300)),
      curve: Curves.easeInOut,
      child: hasFailed ? const _FirstSyncFailed() : const _FirstSyncWorking(),
    );
  }
}

class _FirstSyncWorking extends ConsumerWidget {
  const _FirstSyncWorking();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The pull already accumulates a count per entity type; it was only ever
    // shown on the sync status screen, which is three taps into Settings.
    final counts =
        ref
            .watch(
              syncProgressProvider.select(
                (a) => a.whenData((p) => p.entityCounts),
              ),
            )
            .valueOrNull ??
        const <String, int>{};
    final total = counts.values.fold<int>(0, (a, b) => a + b);

    return _Bar(
      background: AppTheme.brandBlue.withValues(alpha: 0.12),
      foreground: context.primaryText,
      leading: const SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
      message: total > 0
          ? l10n(context).gettingYourDataCount(total)
          : l10n(context).gettingYourData,
    );
  }
}

class _FirstSyncFailed extends ConsumerStatefulWidget {
  const _FirstSyncFailed();

  @override
  ConsumerState<_FirstSyncFailed> createState() => _FirstSyncFailedState();
}

class _FirstSyncFailedState extends ConsumerState<_FirstSyncFailed> {
  bool _retrying = false;

  Future<void> _retry() async {
    setState(() => _retrying = true);
    try {
      final service = await ref.read(syncServiceProvider.future);
      await service.syncNow();
      ref.invalidate(hasCompletedFirstSyncProvider);
    } catch (_) {
      // The banner stays up, which is the feedback — a snackbar on top of a
      // bar that already says the same thing adds nothing.
    } finally {
      if (mounted) setState(() => _retrying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final message = l10n(context).couldNotLoadYourData;

    // A bar that only appears visually is invisible to a screen reader user,
    // who is then the one person with no idea why the app is empty.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      SemanticsService.sendAnnouncement(
        View.of(context),
        message,
        Directionality.of(context),
      );
    });

    return _Bar(
      background: Theme.of(context).colorScheme.error.withValues(alpha: 0.12),
      foreground: context.dangerText,
      leading: Icon(Icons.cloud_off, size: 16, color: context.dangerText),
      message: message,
      action: TextButton(
        onPressed: _retrying ? null : _retry,
        child: Text(l10n(context).tryAgain),
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  final Color background;
  final Color foreground;
  final Widget leading;
  final String message;
  final Widget? action;

  const _Bar({
    required this.background,
    required this.foreground,
    required this.leading,
    required this.message,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: background,
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      child: Row(
        children: [
          leading,
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: foreground),
            ),
          ),
          if (action != null) action!,
        ],
      ),
    );
  }
}
