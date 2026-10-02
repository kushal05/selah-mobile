import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/theme_colors.dart';
import 'tap_target.dart';

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

  /// Shown last, after any count — a chevron on a pill that opens or closes
  /// something, so it reads as a control with more behind it rather than as a
  /// choice in its own right.
  final IconData? trailingIcon;

  /// For a pill that opens and closes a panel: whether that panel is open.
  /// Null for an ordinary choice. Announced by screen readers, which cannot see
  /// the chevron that says the same thing on screen.
  final bool? expanded;

  /// The accent this filter belongs to, usually its tab's colour.
  final Color accent;

  /// Draws the pill smaller without shrinking what you can tap.
  ///
  /// The visible chip loses a few points of height, type, icon and padding; the
  /// tap target stays 44. Those are different measurements and only one of them
  /// is an accessibility floor — a chip that merely looks smaller is a style
  /// choice, while a 36pt target is a miss for anyone without precise hands.
  final bool dense;

  /// What a dense pill is *drawn* at. Deliberately under
  /// [AppTheme.minTapTarget]; [TapTarget] holds the touch area to the floor, so
  /// the chip is smaller to look at without being smaller to hit.
  static const double densePaintHeight = 36;

  const FilterPill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.count,
    this.trailingIcon,
    this.expanded,
    this.accent = AppTheme.brandBlue,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final glyph = AppTheme.semanticFor(accent, brightness);
    final ink = AppTheme.inkOnTintFor(accent, brightness);
    final fg = selected ? ink : context.primaryText;

    final pill = Semantics(
      button: true,
      selected: selected,
      expanded: expanded,
      child: Material(
        color: selected
            ? glyph.withValues(alpha: AppTheme.alphaLight)
            : context.cardSurface,
        borderRadius: AppTheme.borderRadius2XL,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppTheme.borderRadius2XL,
          child: Container(
            // 44 is why these were all slightly different heights before. A
            // dense chip is drawn at 36 and the wrapper below restores the
            // target, so this is the painted height, not the tappable one.
            constraints: BoxConstraints(
              minHeight: dense ? densePaintHeight : AppTheme.minTapTarget,
            ),
            padding: EdgeInsets.symmetric(horizontal: dense ? 10 : 12),
            decoration: BoxDecoration(
              borderRadius: AppTheme.borderRadius2XL,
              border: Border.all(
                color: selected
                    ? glyph.withValues(alpha: 0.4)
                    : context.hairline,
              ),
            ),
            // Centred, but only as large as the label — not as large as the
            // room on offer. `alignment:` on the Container centred by expanding
            // to fill any bounded width, so in a Wrap every pill grew to a full
            // row and the song filter dialog listed its 25 keys one per line.
            // The factors make it shrink-wrap instead. A parent that *requires*
            // a width — Prayers puts each pill in an Expanded — still gets it,
            // because tight constraints override the factor; only the
            // unasked-for growth is gone.
            child: Center(
              widthFactor: 1,
              heightFactor: 1,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(icon,
                        size: dense ? AppTheme.iconSM : AppTheme.iconMD,
                        color: selected ? glyph : context.mutedText),
                    SizedBox(width: dense ? 4 : 6),
                  ],
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: dense ? 13 : 14,
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
                  if (trailingIcon != null) ...[
                    SizedBox(width: dense ? 2 : 4),
                    Icon(trailingIcon,
                        size: dense ? AppTheme.iconSM : AppTheme.iconMD,
                        color: selected ? glyph : context.mutedText),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );

    if (!dense) return pill;

    // Drawn at 36, tapped at 44.
    return TapTarget(onTap: onTap, child: pill);
  }
}
