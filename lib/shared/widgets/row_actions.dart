import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/theme_colors.dart';

/// One action offered by a list row's overflow menu.
class RowAction {
  final IconData icon;
  final String label;
  final VoidCallback onSelected;

  /// Renders in the error colour, for destructive actions.
  final bool isDestructive;

  const RowAction({
    required this.icon,
    required this.label,
    required this.onSelected,
    this.isDestructive = false,
  });
}

/// The visible `⋮` equivalent of a row's swipe and long-press actions.
///
/// Swipe and long-press are the two gestures novice and older users most
/// reliably fail to discover, and both are hard with reduced dexterity — a
/// long-press means holding still for 500ms, which a tremor defeats. Neither
/// registers a custom semantic action either, so a screen reader cannot reach
/// them at all.
///
/// This does not remove those gestures; it gives the same actions a visible,
/// keyboard- and screen-reader-reachable home for everyone who never found
/// them.
class RowOverflowButton extends StatelessWidget {
  final List<RowAction> actions;

  /// Names the row in the button's accessible label, so a screen reader user
  /// hears "More actions for Psalm 23 notes" rather than a wall of identical
  /// "More actions" buttons.
  final String? semanticLabel;

  const RowOverflowButton({
    super.key,
    required this.actions,
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    if (actions.isEmpty) return const SizedBox.shrink();

    return PopupMenuButton<RowAction>(
      icon: const Icon(Icons.more_vert_rounded),
      iconSize: AppTheme.iconBase,
      // 44x44 is the accessible minimum; the default IconButton box is fine
      // but the icon alone is not.
      constraints: const BoxConstraints(minWidth: 200),
      padding: const EdgeInsets.all(10),
      tooltip: semanticLabel == null
          ? 'More actions'
          : 'More actions for $semanticLabel',
      color: context.cardSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radius2XL),
      ),
      onSelected: (action) => action.onSelected(),
      itemBuilder: (context) => [
        for (final action in actions)
          PopupMenuItem<RowAction>(
            value: action,
            height: 48,
            child: Row(
              children: [
                Icon(
                  action.icon,
                  size: AppTheme.iconBase,
                  color: action.isDestructive
                      ? AppTheme.error
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 12),
                Text(
                  action.label,
                  style: TextStyle(
                    fontSize: 16,
                    color: action.isDestructive
                        ? AppTheme.error
                        : context.primaryText,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
