import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../colored_badge.dart';

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
                      // Folder name + date row
                      if (folderName != null || noteDate != null)
                        Row(
                          children: [
                            if (folderName != null) ...[
                              Icon(Icons.folder_outlined,
                                  size: AppTheme.iconXS,
                                  color: AppTheme.hintColor),
                              const SizedBox(width: AppTheme.spacing3),
                              Flexible(
                                child: Text(
                                  folderName!,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: AppTheme.unselectedColor,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                            const Spacer(),
                            if (noteDate != null)
                              Text(
                                _formatNoteDate(noteDate!),
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: AppTheme.hintColor,
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
                                color: AppTheme.hintColor),
                            const SizedBox(width: AppTheme.spacing3),
                            Flexible(
                              child: Text(
                                preacherName!,
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

                      // Title
                      if (folderName != null || noteDate != null || preacherName != null)
                        const SizedBox(height: AppTheme.spacing6),
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

                      // Preview text
                      if (preview != null && preview!.isNotEmpty) ...[
                        const SizedBox(height: AppTheme.spacing7),
                        Text(
                          preview!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppTheme.unselectedColor,
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

                // Chevron
                Padding(
                  padding: const EdgeInsets.only(left: AppTheme.spacing8, top: AppTheme.spacing10),
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
