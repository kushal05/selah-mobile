import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/theme_colors.dart';

/// A filter the user turns on and off: a saved search, a status, a scale.
///
/// Four screens had written their own `_FilterChip`, differing in corner
/// radius (8, 14 and 20), font size (13 and 14), padding, and whether a
/// selected chip was tinted, filled or outlined — so the same control looked
/// like a different control on each tab. Only one of the four resolved its
/// colours per theme.
///
/// The differences that were real are kept as options: some filters carry an
/// icon, the prayer filters carry a count. Everything else is settled here.
///
/// Named `FilterPill` rather than `FilterChip` because Material already
/// defines the latter, and two same-named widgets in scope is how the
/// duplication started.
class FilterPill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// Shown before the label — a glyph for the kind of thing being filtered.
  final IconData? icon;

  /// Shown after the label, for filters over a countable set.
  final int? count;

  /// The accent this filter belongs to, usually its tab's colour.
  final Color accent;

  const FilterPill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.count,
    this.accent = AppTheme.brandBlue,
  });

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final glyph = AppTheme.accentOnTintFor(accent, brightness);
    final ink = AppTheme.inkOnTintFor(accent, brightness);
    final fg = selected ? ink : context.primaryText;

    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected
            ? glyph.withValues(alpha: AppTheme.alphaLight)
            : context.cardSurface,
        borderRadius: AppTheme.borderRadius2XL,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppTheme.borderRadius2XL,
          child: Container(
            // 44 is the accessible minimum, and it is why these were all
            // slightly different heights before.
            constraints: const BoxConstraints(minHeight: 44),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: AppTheme.borderRadius2XL,
              border: Border.all(
                color: selected
                    ? glyph.withValues(alpha: 0.4)
                    : context.hairline,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: AppTheme.iconMD, color: selected ? glyph : context.mutedText),
                  const SizedBox(width: 6),
                ],
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight:
                          selected ? FontWeight.w600 : FontWeight.w500,
                      color: fg,
                    ),
                  ),
                ),
                if (count != null) ...[
                  const SizedBox(width: 6),
                  Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: selected ? ink : context.mutedText,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
