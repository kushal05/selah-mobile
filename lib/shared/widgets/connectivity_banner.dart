import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';

/// Provider that streams connectivity state
final connectivityProvider = StreamProvider<bool>((ref) {
  return Connectivity().onConnectivityChanged.map(
    (results) => results.any((r) => r != ConnectivityResult.none),
  );
});

/// Animated banner shown when the device is offline.
/// Slides in from the top with an amber glass style when offline,
/// and slides out smoothly when reconnected.
class ConnectivityBanner extends ConsumerWidget {
  const ConnectivityBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connectivity = ref.watch(connectivityProvider);

    final bool isOffline = connectivity.whenOrNull(data: (v) => !v) ?? false;

    return AnimatedSize(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        transitionBuilder: (child, animation) {
          final slide = Tween<Offset>(
            begin: const Offset(0, -1),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOut));
          return SlideTransition(position: slide, child: child);
        },
        child: isOffline
            ? _OfflineBanner(key: const ValueKey('offline'))
            : const SizedBox.shrink(key: ValueKey('online')),
      ),
    );
  }
}

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: AppTheme.spacing8, horizontal: AppTheme.spacing16),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: AppTheme.alphaLightMed),
        border: Border(
          bottom: BorderSide(
            color: Colors.amber.shade600.withValues(alpha: AppTheme.alphaStrong),
            width: 0.8,
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.wifi_off_rounded,
              color: Colors.amber.shade800, size: AppTheme.iconSM + 1),
          const SizedBox(width: AppTheme.spacing8),
          Text(
            'You\'re offline. Changes will sync when reconnected.',
            style: AppTheme.caption.copyWith(
              color: Colors.amber.shade800,
            ),
          ),
        ],
      ),
    );
  }
}
