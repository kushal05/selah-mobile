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
/// title, two-line preview, tag badges, trailing controls — so a prayer in a
/// list looks like a note in a list. The earlier version invented its own
/// layout: a full-width "Log Prayer" button on every card, and the prayer's
/// own words hidden behind an expand chevron.
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

  const PrayTodayCard({
    super.key,
    required this.prayer,
    required this.isLogged,
    required this.onLogPress,
    this.onTap,
    this.onMarkAnswered,
    this.onArchive,
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
              padding: AppTheme.cardPadding,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: AppTheme.iconBadgeSM,
                    height: AppTheme.iconBadgeSM,
                    decoration: BoxDecoration(
                      color:
                          badgeTint.withValues(alpha: AppTheme.alphaLightMed),
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
                            fontWeight:
                                isLogged ? FontWeight.w600 : FontWeight.w500,
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
                            decoration:
                                isLogged ? TextDecoration.lineThrough : null,
                          ),
                        ),
                        if (description.isNotEmpty) ...[
                          const SizedBox(height: AppTheme.spacing7),
                          Text(
                            description,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              height: 1.4,
                            ),
                          ),
                        ],
                        if (metadata.tags.isNotEmpty) ...[
                          const SizedBox(height: AppTheme.spacing10),
                          Wrap(
                            spacing: AppTheme.spacing6,
                            runSpacing: AppTheme.spacing6,
                            children: metadata.tags
                                .take(3)
                                .map((t) => ColoredBadge(
                                    label: t, color: AppTheme.brandBlue))
                                .toList(),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: AppTheme.spacing6),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _LogButton(
                        isLogged: isLogged,
                        accent: accent,
                        done: done,
                        onPressed: onLogPress,
                      ),
                      RowOverflowButton(
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
                    ],
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

/// The session's one action: a round target rather than a full-width banner.
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
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      onTap: isLogged ? null : onPressed,
      child: Tooltip(
        message: label,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Material(
            color: (isLogged ? done : accent)
                .withValues(alpha: AppTheme.alphaLightMed),
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: isLogged ? null : onPressed,
              child: Icon(
                Icons.check_rounded,
                size: AppTheme.iconBase,
                color: isLogged ? done : accent,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
