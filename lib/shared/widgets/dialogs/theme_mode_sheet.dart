import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/theme_preferences.dart';
import '../../../core/theme/app_theme.dart';
import '../../../l10n/l10n.dart';

/// Bottom sheet for choosing light, dark, or match-device.
///
/// "Match device" leads and is the default: someone who already reads their
/// phone in dark mode gets a dark app without finding this screen at all.
Future<void> showThemeModeSheet(BuildContext context) {
  return showModalBottomSheet<void>(
      // Defaults to false: a scroll-controlled sheet otherwise draws its
      // top edge behind the notch or Dynamic Island.
      useSafeArea: true,
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => const _ThemeModeSheet(),
  );
}

class _ThemeModeSheet extends ConsumerWidget {
  const _ThemeModeSheet();

  static const _order = [ThemeMode.system, ThemeMode.light, ThemeMode.dark];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(themeModeProvider);
    final theme = Theme.of(context);

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 12),
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: theme.dividerColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
            child: Text(l10n(context).settingsAppearance, style: theme.textTheme.titleLarge),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Text(
              l10n(context).darkIsEasierOnTheEyesForReadingAtNight,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          for (final mode in _order)
            _ThemeModeRow(
              mode: mode,
              selected: mode == current,
              onTap: () => ref.read(themeModeProvider.notifier).set(mode),
            ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _ThemeModeRow extends StatelessWidget {
  final ThemeMode mode;
  final bool selected;
  final VoidCallback onTap;

  const _ThemeModeRow({
    required this.mode,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;

    return Semantics(
      inMutuallyExclusiveGroup: true,
      selected: selected,
      label: '${mode.label}. ${mode.description}',
      excludeSemantics: true,
      button: true,
      // onTap must live on this node: excludeSemantics drops the child's
      // tap action, so without it the control announces as a button but
      // cannot be activated — the exact bug the onTapUp fix removed.
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          color: selected ? accent.withValues(alpha: AppTheme.alphaLight) : null,
          child: Row(
            children: [
              Icon(mode.icon, size: AppTheme.iconXL, color: accent),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      mode.label,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.w500,
                      ),
                    ),
                    Text(
                      mode.description,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected)
                Icon(Icons.check_rounded,
                    size: AppTheme.iconXL, color: accent),
            ],
          ),
        ),
      ),
    );
  }
}
