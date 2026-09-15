import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';

import '../../core/theme/app_theme.dart';

/// Fraction of the row one swipe action occupies.
///
/// 0.18 puts a single action at roughly 72pt on a standard phone — a little
/// under the platform's own, so the row stays the largest thing in the open
/// pane. The Notes list previously asked for 0.45 for two actions, which made
/// each one nearly half again as wide as it needed to be and read as two
/// large blocks rather than controls.
const double _kActionExtent = 0.18;

/// Pane width for [actionCount] actions, as [ActionPane.extentRatio].
double swipePaneExtent(int actionCount) =>
    (_kActionExtent * actionCount).clamp(_kActionExtent, 0.6);

/// One swipe action, built from the same recipe as the dashboard's tinted
/// surfaces: the accent at [AppTheme.alphaLight] behind a 25% border — the
/// same weight as the first-use intro banner — with
/// [AppTheme.accentOnTintFor] for the glyph and [AppTheme.inkOnTintFor] for
/// the label. An open pane then reads as part of the list rather than as two
/// saturated blocks stamped over it.
///
/// [accent] is a palette colour ([AppTheme.error], [AppTheme.brandPurple],
/// [AppTheme.emerald]) — the same value the rest of the app would pass for
/// that meaning, not a bespoke fill. Every foreground is derived from it
/// through the audited helpers, so the tile stays legible in both themes and
/// a colour without a verified ink falls back to the neutral rather than to
/// something unchecked.
///
/// [isFirst]/[isLast] only set the outer margins, so a pane's tiles sit in
/// from the row and the screen edge by the same amount whatever their number.
CustomSlidableAction buildSwipeAction({
  required IconData icon,
  required String label,
  required Color accent,
  required void Function(BuildContext) onPressed,
  bool isFirst = true,
  bool isLast = true,
}) {
  return CustomSlidableAction(
    onPressed: onPressed,
    // CustomSlidableAction defaults its background to Colors.white. The tile
    // inside is inset by its own margins, so that default showed as a white
    // block framing each action — and it is white in dark mode too.
    backgroundColor: Colors.transparent,
    padding: EdgeInsets.zero,
    child: Builder(
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final brightness = isDark ? Brightness.dark : Brightness.light;
        // The same tint the first-use intro banner uses: the adjusted accent
        // at 8%, with a 25% edge. A saturated fill made the actions the
        // loudest thing on the screen; at this weight they read as part of
        // the list rather than as an alert stamped over it.
        final tint = AppTheme.accentOnTintFor(accent, brightness);
        return Container(
          margin: EdgeInsets.only(
            left: isFirst ? AppTheme.spacing8 : 3,
            right: isLast ? AppTheme.spacing8 : 3,
            // Inset vertically so the tiles sit a little shorter than the row
            // they belong to, rather than matching its full height and
            // competing with it.
            top: AppTheme.spacing6,
            bottom: AppTheme.spacing6,
          ),
          decoration: BoxDecoration(
            color: tint.withValues(alpha: AppTheme.alphaLight),
            // Matches the list row beside it, so the open pane reads as one
            // set of objects rather than a card next to two chips.
            borderRadius: AppTheme.borderRadius2XL,
            // A pale tile needs an edge to separate it from a pale row.
            border: Border.all(
              color: tint.withValues(alpha: 0.25),
              width: AppTheme.borderWidthDefault,
            ),
          ),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              // A trash row can be short and the label grows with the user's
              // text size, so scale down rather than overflow.
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      icon,
                      size: AppTheme.iconBase,
                      color: AppTheme.accentOnTintFor(accent,
                          isDark ? Brightness.dark : Brightness.light),
                    ),
                    const SizedBox(height: AppTheme.spacing6),
                    Text(
                      label,
                      maxLines: 1,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppTheme.inkOnTintFor(accent, brightness),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
}
