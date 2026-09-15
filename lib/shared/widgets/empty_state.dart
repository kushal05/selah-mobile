import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../l10n/l10n.dart';

/// The standard "nothing here yet" state.
///
/// An empty screen is the highest-leverage teaching surface in the app: it
/// appears exactly when someone has nothing and most needs direction. The
/// previous per-screen versions pointed at a `+` the user had to find for
/// themselves ("Tap + to add your first Bible promise") in grey text at
/// 2.68:1, which told a newcomer neither what the screen is for nor what to
/// press.
///
/// So the shape here is fixed: say what this screen holds, say it in plain
/// language, and put the actual button in reach.
class EmptyState extends StatelessWidget {
  /// Illustrative icon. Decorative — it is hidden from screen readers, since
  /// [title] and [message] already carry the meaning.
  final IconData icon;

  /// Short statement of fact: 'No prayers yet'.
  final String title;

  /// One or two sentences saying what this screen is *for*. This is the part
  /// that teaches — assume the reader does not know what the feature does.
  final String message;

  /// Label for the primary action, e.g. 'Add your first prayer'.
  final String? actionLabel;

  /// Invoked by the primary button. When null, no button is shown.
  final VoidCallback? onAction;

  /// Optional secondary action, e.g. 'Learn what promises are'.
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  /// Accent for the icon and primary button.
  final Color? accent;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.secondaryLabel,
    this.onSecondary,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    // The accent has to follow the theme: the on-light variants are darkened
    // for a white ground and read as muddy on a dark one.
    final base = accent ?? AppTheme.brandBlue;
    final color = Theme.of(context).brightness == Brightness.dark
        ? AppTheme.accentOnDark(base)
        : AppTheme.accentOnLight(base);

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ExcludeSemantics(
              child: Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 40, color: color),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                height: 1.5,
                // textMuted clears AA at 4.83:1; the previous grey.shade500 was
                // 2.68:1 — unreadable for the audience most likely to be here.
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            if (onAction != null && actionLabel != null) ...[
              const SizedBox(height: 24),
              SizedBox(
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: onAction,
                  icon: const Icon(Icons.add_rounded, size: 20),
                  label: Text(actionLabel!),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: color,
                    foregroundColor:
                        Theme.of(context).brightness == Brightness.dark
                            ? AppTheme.darkScaffold
                            : Colors.white,
                    textStyle: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
            if (onSecondary != null && secondaryLabel != null) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: onSecondary,
                child: Text(
                  secondaryLabel!,
                  style: TextStyle(fontSize: 16, color: color),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The empty state for a Trash view, which needs no call to action.
class EmptyTrashState extends StatelessWidget {
  /// The plural noun for what this trash holds, already localised by the
  /// caller — it is interpolated into a sentence, so it cannot default to a
  /// literal here without leaving one English word in a translated string.
  final String? itemsLabel;
  const EmptyTrashState({super.key, this.itemsLabel});

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Icons.delete_outline_rounded,
      title: l10n(context).trashEmptyTitle,
      message: l10n(context).deletedItemsAppearHereFor30Days(
          itemsLabel ?? l10n(context).trashLabelItems),
      accent: AppTheme.mutedGrey,
    );
  }
}
