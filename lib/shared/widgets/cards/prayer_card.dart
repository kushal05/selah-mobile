import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../colored_badge.dart';

/// Card widget for displaying a prayer in a list.
///
/// Mirrors the visual language of [NoteRow] and [PromiseCard]: a premium white
/// card with a tinted leading icon badge, title, metadata, preview text, and a
/// trailing chevron. The accent (badge tint + status chip) is driven by the
/// prayer's status color.
class PrayerCard extends StatelessWidget {
  final String title;
  final String frequencyLabel;
  final String statusLabel;
  final Color statusColor;
  final String description;
  final List<String> linkedPeopleNames;

  /// Whether to render the status text chip. Set to false when the list is
  /// already scoped to a single status (the chip would just be noise) — the
  /// badge tint still conveys the status.
  final bool showStatusBadge;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const PrayerCard({
    super.key,
    required this.title,
    required this.frequencyLabel,
    required this.statusLabel,
    required this.statusColor,
    this.description = '',
    this.linkedPeopleNames = const [],
    this.showStatusBadge = true,
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      margin: AppTheme.cardMargin,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: AppTheme.borderRadius2XL,
        boxShadow: AppTheme.cardShadow,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: AppTheme.borderRadius2XL,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          borderRadius: AppTheme.borderRadius2XL,
          child: Padding(
            padding: AppTheme.cardPadding,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Leading status icon badge
                Container(
                  width: AppTheme.iconBadgeSM,
                  height: AppTheme.iconBadgeSM,
                  decoration: BoxDecoration(
                    color:
                        statusColor.withValues(alpha: AppTheme.alphaLightMed),
                    borderRadius: AppTheme.borderRadiusLG,
                  ),
                  child: Icon(
                    Icons.favorite_border,
                    color: statusColor,
                    size: AppTheme.iconLG,
                  ),
                ),
                const SizedBox(width: AppTheme.spacing14),

                // Content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Title
                      Text(
                        title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          height: 1.2,
                          color: AppTheme.textDark,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),

                      const SizedBox(height: AppTheme.spacing6),

                      // Frequency + status badge
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              frequencyLabel,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: AppTheme.unselectedColor,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (showStatusBadge) ...[
                            const SizedBox(width: AppTheme.spacing8),
                            ColoredBadge(
                                label: statusLabel, color: statusColor),
                          ],
                        ],
                      ),

                      // Description preview
                      if (description.isNotEmpty) ...[
                        const SizedBox(height: AppTheme.spacing7),
                        Text(
                          description,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppTheme.unselectedColor,
                            height: 1.4,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],

                      // Linked people
                      if (linkedPeopleNames.isNotEmpty) ...[
                        const SizedBox(height: AppTheme.spacing10),
                        Row(
                          children: [
                            Icon(
                              Icons.people_outline,
                              size: AppTheme.iconXS,
                              color: AppTheme.hintColor,
                            ),
                            const SizedBox(width: AppTheme.spacing4),
                            Expanded(
                              child: Text(
                                linkedPeopleNames.join(', '),
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: AppTheme.unselectedColor,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),

                // Chevron
                Padding(
                  padding: const EdgeInsets.only(
                    left: AppTheme.spacing8,
                    top: AppTheme.spacing10,
                  ),
                  child: Icon(
                    Icons.chevron_right_rounded,
                    size: AppTheme.iconBase,
                    color: AppTheme.chevronColor,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
