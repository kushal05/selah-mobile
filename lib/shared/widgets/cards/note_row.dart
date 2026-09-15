import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../colored_badge.dart';
import '../row_actions.dart';
import '../../../core/theme/theme_colors.dart';

/// Displays a note item as a premium white card in the notes list.
class NoteRow extends StatelessWidget {
  final String title;
  final String? preview;
  final List<String> tags;
  final String? preacherName;
  final DateTime? noteDate;
  final String? folderName;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Actions also available by swipe or long-press. Rendered as a visible
  /// overflow menu so they are discoverable, and reachable by screen readers,
  /// which cannot perform either gesture.
  final List<RowAction> actions;

  const NoteRow({
    super.key,
    required this.title,
    this.preview,
    this.tags = const [],
    this.preacherName,
    this.noteDate,
    this.folderName,
    this.onTap,
    this.onLongPress,
    this.actions = const [],
  });

  String _formatNoteDate(DateTime date) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      margin: AppTheme.cardMargin,
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
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
                // Left icon
                Container(
                  width: AppTheme.iconBadgeSM,
                  height: AppTheme.iconBadgeSM,
                  decoration: BoxDecoration(
                    color: AppTheme.brandPurple.withValues(alpha: AppTheme.alphaLightMed),
                    borderRadius: AppTheme.borderRadiusLG,
                  ),
                  child: const Icon(
                    Icons.description_outlined,
                    color: AppTheme.brandPurple,
                    size: AppTheme.iconLG,
                  ),
                ),
                const SizedBox(width: AppTheme.spacing14),

                // Content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Folder name + date. A Row with a Spacer overflows once
                      // the text scale grows — the date has no give. Wrap lets
                      // the date drop to its own line instead of clipping.
                      if (folderName != null || noteDate != null)
                        Wrap(
                          spacing: AppTheme.spacing8,
                          runSpacing: AppTheme.spacing3,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            if (folderName != null)
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.folder_outlined,
                                      size: AppTheme.iconXS,
                                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                                  const SizedBox(width: AppTheme.spacing3),
                                  ConstrainedBox(
                                    // A flat 160 fits a 420pt screen and
                                    // overflows a 320pt one; cap it against
                                    // the actual width instead.
                                    constraints: BoxConstraints(
                                      maxWidth: math.min(
                                        160,
                                        MediaQuery.sizeOf(context).width * 0.4,
                                      ),
                                    ),
                                    child: Text(
                                      folderName!,
                                      style: theme.textTheme.labelSmall
                                          ?.copyWith(
                                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            if (noteDate != null)
                              Text(
                                _formatNoteDate(noteDate!),
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                              ),
                          ],
                        ),

                      // Preacher name row
                      if (preacherName != null) ...[
                        const SizedBox(height: AppTheme.spacing3),
                        Row(
                          children: [
                            Icon(Icons.person_outline,
                                size: AppTheme.iconXS,
                                color: Theme.of(context).colorScheme.onSurfaceVariant),
                            const SizedBox(width: AppTheme.spacing3),
                            Flexible(
                              child: Text(
                                preacherName!,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],

                      // Title
                      if (folderName != null || noteDate != null || preacherName != null)
                        const SizedBox(height: AppTheme.spacing6),
                      Text(
                        title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          height: 1.2,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),

                      // Preview text
                      if (preview != null && preview!.isNotEmpty) ...[
                        const SizedBox(height: AppTheme.spacing7),
                        Text(
                          preview!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                            height: 1.4,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],

                      // Tags
                      if (tags.isNotEmpty) ...[
                        const SizedBox(height: AppTheme.spacing10),
                        Wrap(
                          spacing: AppTheme.spacing6,
                          runSpacing: AppTheme.spacing6,
                          children: tags
                              .map((tag) => ColoredBadge(label: tag, color: AppTheme.brandPurple))
                              .toList(),
                        ),
                      ],
                    ],
                  ),
                ),

                // Overflow menu when the row has actions, chevron otherwise.
                if (actions.isNotEmpty)
                  RowOverflowButton(actions: actions, semanticLabel: title)
                else
                  Padding(
                    padding: EdgeInsets.only(
                        left: AppTheme.spacing8, top: AppTheme.spacing10),
                    child: Icon(
                      Icons.chevron_right_rounded,
                      size: AppTheme.iconBase,
                      color: context.decorativeInk,
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
