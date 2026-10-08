import 'package:flutter/material.dart';

import '../../../../core/providers/motion_preferences.dart';
import '../../../../core/sync/models/prayer_model.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/theme_colors.dart';
import '../../../../l10n/l10n.dart';
import '../../../../shared/widgets/colored_badge.dart';
import '../../../../shared/widgets/row_actions.dart';
import '../../domain/models/prayer_metadata_codec.dart';

/// One prayer in the Pray Today session.
///
/// Built from the same parts as [NoteRow] — icon badge, muted meta line,
/// title, preview, tag badges, trailing controls — so a prayer in a list looks
/// like a note in a list. The first version invented its own layout: a
/// full-width "Log Prayer" button on every card, and the prayer's own words
/// hidden behind an expand chevron.
///
/// The words are not hidden now, but they can be opened in place: one line by
/// default, and an arrow that shows the rest, so a long prayer can be read
/// while praying without leaving the session for its detail page. The arrow
/// appears only when one line does not hold the description.
///
/// The two controls sit together at the trailing edge: logging is the
/// session's action, and the overflow carries the state changes that
/// otherwise mean leaving the session and coming back.
class PrayTodayCard extends StatelessWidget {
  final PrayerModel prayer;
  final bool isLogged;
  final VoidCallback onLogPress;
  final VoidCallback? onTap;
  final VoidCallback? onMarkAnswered;
  final VoidCallback? onArchive;

  /// Whether the description is showing in full. Held by the screen rather
  /// than here: the list disposes cards that scroll away, and a prayer opened
  /// to read should still be open when it scrolls back.
  final bool isExpanded;
  final VoidCallback? onToggleExpanded;

  const PrayTodayCard({
    super.key,
    required this.prayer,
    required this.isLogged,
    required this.onLogPress,
    this.onTap,
    this.onMarkAnswered,
    this.onArchive,
    this.isExpanded = false,
    this.onToggleExpanded,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strings = l10n(context);
    final brightness = theme.brightness;
    final metadata = decodePrayerMetadata(prayer.category);
    final accent = AppTheme.accentOnTintFor(AppTheme.brandBlue, brightness);
    final done = AppTheme.semanticFor(AppTheme.success, brightness);
    final badgeTint = isLogged ? done : accent;
    final description =
        prayer.content.split('\n<!-- updates -->').first.trim();
    final hasDetails = description.isNotEmpty || metadata.tags.isNotEmpty;

    return AnimatedOpacity(
      opacity: isLogged ? 0.65 : 1.0,
      duration: context.motion(const Duration(milliseconds: 250)),
      child: Container(
        margin: AppTheme.cardMargin,
        decoration: BoxDecoration(
          color: theme.cardTheme.color,
          borderRadius: AppTheme.borderRadius2XL,
          boxShadow: AppTheme.cardShadow,
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: AppTheme.borderRadius2XL,
          child: InkWell(
            onTap: onTap,
            borderRadius: AppTheme.borderRadius2XL,
            child: Padding(
              // With a description or tags below, they carry the card's bottom
              // padding themselves: see [_DetailsSection].
              padding: hasDetails
                  ? AppTheme.cardPadding.copyWith(bottom: 0)
                  : AppTheme.cardPadding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: AppTheme.iconBadgeSM,
                        height: AppTheme.iconBadgeSM,
                        decoration: BoxDecoration(
                          color: badgeTint.withValues(
                              alpha: AppTheme.alphaLightMed),
                          borderRadius: AppTheme.borderRadiusLG,
                        ),
                        child: Icon(
                          isLogged
                              ? Icons.check_circle_outline_rounded
                              : Icons.favorite_outline_rounded,
                          color: badgeTint,
                          size: AppTheme.iconLG,
                        ),
                      ),
                      const SizedBox(width: AppTheme.spacing14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isLogged
                                  ? '${prayer.frequency.displayName}  ·  ${strings.prayed}'
                                  : prayer.frequency.displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: isLogged ? done : context.mutedText,
                                fontWeight: isLogged
                                    ? FontWeight.w600
                                    : FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: AppTheme.spacing6),
                            Text(
                              prayer.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                                height: 1.2,
                                color: theme.colorScheme.onSurface,
                                decoration: isLogged
                                    ? TextDecoration.lineThrough
                                    : null,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: AppTheme.spacing6),
                      // The same height as the badge, so the badge, the log
                      // button and the overflow share one centre line.
                      // Unsized, this row took the height of its tallest
                      // child — the overflow's 48pt default — and centred the
                      // 40pt log button in that, so both sat lower than the
                      // 44pt badge beside them.
                      SizedBox(
                        height: AppTheme.iconBadgeSM,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            _LogButton(
                              isLogged: isLogged,
                              accent: accent,
                              done: done,
                              onPressed: onLogPress,
                            ),
                            // 44 square, not the IconButton's 48 default:
                            // the arrow column below is 44 wide, and the two
                            // have to share a centre for the arrow to sit
                            // under the ⋮. 44 is still the full tap target.
                            SizedBox.square(
                              dimension: AppTheme.minTapTarget,
                              child: RowOverflowButton(
                                semanticLabel: prayer.title,
                                actions: [
                                  if (onMarkAnswered != null)
                                    RowAction(
                                      icon: Icons.check_circle_outline_rounded,
                                      label: strings.markAsAnswered,
                                      onSelected: onMarkAnswered!,
                                    ),
                                  if (onArchive != null)
                                    RowAction(
                                      icon: Icons.archive_outlined,
                                      label: strings.archive,
                                      onSelected: onArchive!,
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  // Below the controls, the description and tags run the full
                  // width — the controls take only the top 44pt, and squeezed
                  // into the column between them the description showed three
                  // words, or wrapped an opened prayer into nine short lines.
                  // Indented to start under the title.
                  if (hasDetails)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(
                          start: AppTheme.iconBadgeSM + AppTheme.spacing14),
                      child: _DetailsSection(
                        description: description,
                        tags: metadata.tags.take(3).toList(),
                        expanded: isExpanded,
                        onToggle: onToggleExpanded,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          height: 1.4,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The prayer's own words — one line, or all of them — and its tags, down to
/// the card's bottom edge.
///
/// The arrow is offered only when one line does not hold the description,
/// measured at the width the text really gets (less the arrow) and at the
/// reader's text size — a description that fits at 100% can need the arrow at
/// 130%.
///
/// With the arrow, the whole section is the control, not just the arrow: an
/// 18pt glyph alone is far under the 44pt floor. The section takes in the
/// card's bottom padding and the tags so that the 44pt is made of space the
/// card has anyway. Held to 44pt on its own, a collapsed line left a 20pt band
/// of nothing beneath it, above the tags or the card's edge. Taps anywhere
/// else on the card still open the prayer.
class _DetailsSection extends StatelessWidget {
  final String description;
  final List<String> tags;
  final bool expanded;
  final VoidCallback? onToggle;
  final TextStyle? style;

  const _DetailsSection({
    required this.description,
    required this.tags,
    required this.expanded,
    required this.onToggle,
    required this.style,
  });

  /// The arrow's column: as wide as the overflow button's tap target, so the
  /// arrow sits centred under the ⋮ and the controls read as one column.
  static const double _arrowColumn = AppTheme.minTapTarget;

  @override
  Widget build(BuildContext context) {
    final tagRow = tags.isEmpty
        ? null
        : Padding(
            padding: const EdgeInsets.only(top: AppTheme.spacing10),
            child: Wrap(
              spacing: AppTheme.spacing6,
              runSpacing: AppTheme.spacing6,
              children: [
                for (final t in tags)
                  ColoredBadge(label: t, color: AppTheme.brandBlue),
              ],
            ),
          );
    // The bottom padding the card left off for this section to carry.
    final bottom = SizedBox(height: AppTheme.cardPadding.bottom);

    return LayoutBuilder(builder: (context, constraints) {
      var fitsOneLine = true;
      var lineHeight = 0.0;
      if (description.isNotEmpty) {
        final painter = TextPainter(
          text: TextSpan(text: description, style: style),
          maxLines: 1,
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout(maxWidth: constraints.maxWidth - _arrowColumn);
        fitsOneLine = !painter.didExceedMaxLines;
        lineHeight = painter.height;
        painter.dispose();
      }

      // Short enough to read whole: no arrow, nothing to tap.
      if (fitsOneLine || onToggle == null) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (description.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: AppTheme.spacing7),
                child: Text(
                  description,
                  maxLines: onToggle == null ? 2 : 1,
                  overflow: TextOverflow.ellipsis,
                  style: style,
                ),
              ),
            ?tagRow,
            bottom,
          ],
        );
      }

      final strings = l10n(context);
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        excludeFromSemantics: true,
        onTap: onToggle,
        child: ConstrainedBox(
          // At least 44pt tall, the floor for anything tapped.
          constraints: const BoxConstraints(minHeight: AppTheme.minTapTarget),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // The semantics cover the description only: the tags are read as
              // tags, not as part of the button.
              Semantics(
                button: true,
                expanded: expanded,
                onTapHint: expanded ? strings.seeLess : strings.seeMore,
                onTap: onToggle,
                child: Padding(
                  // The same 7pt gap below the title as without an arrow.
                  padding: const EdgeInsets.only(top: AppTheme.spacing7),
                  child: Row(
                    // Beside the first line in both states, so the arrow does
                    // not move out from under the finger that tapped it.
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          description,
                          maxLines: expanded ? null : 1,
                          overflow: expanded
                              ? TextOverflow.visible
                              : TextOverflow.ellipsis,
                          style: style,
                        ),
                      ),
                      // One line tall, the glyph centred on it and spilling
                      // over: at its own height the arrow is taller than the
                      // line and pushed the tags 3pt further down than a
                      // description without one.
                      SizedBox(
                        width: _arrowColumn,
                        height: lineHeight,
                        child: OverflowBox(
                          maxHeight: double.infinity,
                          child: Icon(
                            expanded
                                ? Icons.expand_less_rounded
                                : Icons.expand_more_rounded,
                            size: AppTheme.iconLG,
                            color: context.mutedText,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              ?tagRow,
              bottom,
            ],
          ),
        ),
      );
    });
  }
}

/// The session's one action: a round target rather than a full-width banner.
///
/// A 40pt circle in a 44pt tap target, the floor for anything tapped; the
/// circle alone had been the target.
class _LogButton extends StatelessWidget {
  final bool isLogged;
  final Color accent;
  final Color done;
  final VoidCallback onPressed;

  const _LogButton({
    required this.isLogged,
    required this.accent,
    required this.done,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final label = isLogged ? l10n(context).prayed : l10n(context).logPrayer;
    final color = isLogged ? done : accent;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      onTap: isLogged ? null : onPressed,
      child: Tooltip(
        message: label,
        child: SizedBox.square(
          dimension: AppTheme.minTapTarget,
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: isLogged ? null : onPressed,
              child: Center(
                // Ink, not a Container: it paints on the Material, so the
                // splash shows over the tint instead of under it.
                child: Ink(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: AppTheme.alphaLightMed),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.check_rounded,
                    size: AppTheme.iconBase,
                    color: color,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
