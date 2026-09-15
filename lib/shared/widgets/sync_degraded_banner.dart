import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/sync/engine/sync_state_machine.dart';
import '../../core/sync/providers/sync_providers.dart';
import '../../core/theme/app_theme.dart';
import 'connectivity_banner.dart';
import '../../core/services/user_facing_error.dart';
import '../../core/providers/motion_preferences.dart';
import '../../l10n/l10n.dart';
import '../../core/theme/theme_colors.dart';

/// Animated banner shown at the top of the app shell when the sync engine
/// has entered the `degraded` state (too many consecutive failures —
/// automated triggers suppressed until the user takes action).
///
/// Suppressed when the device is offline: the [ConnectivityBanner] already
/// communicates that, and showing both would be noisy. Tapping the banner
/// triggers an explicit manual sync via [SyncService.syncNow], which clears
/// the degraded state inside the engine and gives recovery a real attempt.
class SyncDegradedBanner extends ConsumerWidget {
  const SyncDegradedBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOffline =
        ref.watch(connectivityProvider).whenOrNull(data: (v) => !v) ?? false;

    // Only rebuild when the sync state enum changes, not on every progress
    // emission — the banner doesn't care about percentages or counts.
    final syncState = ref.watch(
      syncProgressProvider.select((async) => async.whenData((p) => p.state)),
    );
    final isDegraded =
        syncState.whenOrNull(data: (s) => s == SyncEngineState.degraded) ??
            false;

    final show = isDegraded && !isOffline;

    return AnimatedSize(
      duration: context.motion(const Duration(milliseconds: 300)),
      curve: Curves.easeInOut,
      child: AnimatedSwitcher(
        duration: context.motion(const Duration(milliseconds: 300)),
        transitionBuilder: (child, animation) {
          final slide = Tween<Offset>(
            begin: const Offset(0, -1),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOut));
          return SlideTransition(position: slide, child: child);
        },
        child: show
            ? _DegradedBanner(key: const ValueKey('degraded'))
            : const SizedBox.shrink(key: ValueKey('healthy')),
      ),
    );
  }
}

class _DegradedBanner extends ConsumerStatefulWidget {
  const _DegradedBanner({super.key});

  @override
  ConsumerState<_DegradedBanner> createState() => _DegradedBannerState();
}

class _DegradedBannerState extends ConsumerState<_DegradedBanner> {
  bool _retrying = false;

  Future<void> _retry() async {
    if (_retrying) return;
    setState(() => _retrying = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(syncInitializedProvider.future);
      final service = await ref.read(syncServiceProvider.future);
      final result = await service.syncNow();
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            result.success
                ? 'Sync recovered — pushed ${result.operationsPushed}, '
                    'pulled ${result.operationsPulled}'
                : 'Sync failed: ${result.error ?? "unknown error"}',
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: result.success ? null : Colors.red.shade600,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(UserFacingError.message(e, action: 'sync your data')),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppTheme.errorSurface,
        ),
      );
    } finally {
      if (mounted) setState(() => _retrying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _retry,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
            vertical: AppTheme.spacing8,
            horizontal: AppTheme.spacing16,
          ),
          decoration: BoxDecoration(
            color:
                Colors.deepOrange.withValues(alpha: AppTheme.alphaLightMed),
            border: Border(
              bottom: BorderSide(
                color: Colors.deepOrange.shade600
                    .withValues(alpha: AppTheme.alphaStrong),
                width: 0.8,
              ),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.warning_amber_rounded,
                  color: context.warningText,
                  size: AppTheme.iconSM + 1),
              const SizedBox(width: AppTheme.spacing8),
              Flexible(
                child: Text(
                  l10n(context).syncIsDegradedTapToRetry,
                  style: AppTheme.caption.copyWith(
                    color: context.warningText,
                  ),
                ),
              ),
              if (_retrying) ...[
                const SizedBox(width: AppTheme.spacing8),
                SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    valueColor:
                        AlwaysStoppedAnimation(Colors.deepOrange.shade800),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
