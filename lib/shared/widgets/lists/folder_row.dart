import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

import '../../../core/sync/models/folder_model.dart';

/// Displays a folder item in the notes list with hierarchical support
class FolderRow extends StatelessWidget {
  final String title;
  final int noteCount;
  final int? folderCount;
  final int depth;
  final bool isExpanded;
  final bool isActive;
  final bool hasChildren;
  final FolderVisibility? visibility;
  final Color? accentColor;
  final VoidCallback? onTap;
  final VoidCallback? onExpandToggle;
  final VoidCallback? onLongPress;

  const FolderRow({
    super.key,
    required this.title,
    required this.noteCount,
    this.folderCount,
    this.depth = 0,
    this.isExpanded = false,
    this.isActive = false,
    this.hasChildren = false,
    this.visibility,
    this.accentColor,
    this.onTap,
    this.onExpandToggle,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Calculate indentation based on depth (16dp per level)
    final double indentation = 16.0 + (depth * 16.0);

    return Material(
      color: isActive ? Colors.grey.shade100 : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Container(
          height: 56,
          padding: EdgeInsets.only(
            left: indentation,
            right: 16,
          ),
          child: Row(
            children: [
              // Folder icon
              Icon(
                isActive ? Icons.folder_open_rounded : Icons.folder_rounded,
                size: 24,
                color: isActive
                    ? (accentColor ?? AppTheme.brandPurple)
                    : (accentColor ?? AppTheme.brandPurple).withValues(alpha: 0.8),
              ),
              const SizedBox(width: 12),

              // Folder info
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (visibility != null &&
                            visibility != FolderVisibility.personal) ...[
                          const SizedBox(width: 6),
                          Icon(
                            visibility!.icon,
                            size: 14,
                            color: Colors.grey.shade500,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _buildMetaText(),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),

              // Expand/collapse chevron (only if has children)
              if (hasChildren)
                GestureDetector(
                  onTap: onExpandToggle,
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Icon(
                      isExpanded
                          ? Icons.expand_more_rounded
                          : Icons.chevron_right_rounded,
                      size: 20,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _buildMetaText() {
    if (folderCount != null && folderCount! > 0) {
      return '$folderCount folders • $noteCount notes';
    }
    return '$noteCount notes';
  }
}
