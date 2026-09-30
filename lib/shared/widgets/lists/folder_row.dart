import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../l10n/l10n.dart';

import '../../../core/sync/models/folder_model.dart';
import '../../../core/theme/theme_colors.dart';

/// Displays a folder item in the notes list with hierarchical support
class FolderRow extends StatelessWidget {
  final String title;
  /// Null when the notes could not be read.
  ///
  /// It was a plain int defaulting to zero from `valueOrNull ?? []`, so a
  /// failed read labelled every folder "0 notes" — a count of the user's own
  /// work, stated from a query that never returned.
  final int? noteCount;

  /// Whether the notes read actually failed, as opposed to not having
  /// returned yet. Both leave [noteCount] null, but only one of them is
  /// something to tell the user: every cold open passes through the other.
  final bool countFailed;
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
    this.countFailed = false,
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
                            color: context.mutedText,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _buildMetaText(context),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: context.mutedText,
                      ),
                    ),
                  ],
                ),
              ),

              // Expand/collapse chevron (only if has children)
              if (hasChildren)
                Semantics(
                  button: true,
                  label: isExpanded
                      ? l10n(context).collapseFolder
                      : l10n(context).expandFolder,
                  child: GestureDetector(
                    onTap: onExpandToggle,
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Icon(
                        isExpanded
                            ? Icons.expand_more_rounded
                            : Icons.chevron_right_rounded,
                        size: 20,
                        color: context.mutedText,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _buildMetaText(BuildContext context) {
    // Three states, not two. A null count that merely has not arrived says
    // nothing at all — announcing "Count unavailable" on every cold open is a
    // failure message the widget then has to retract.
    final String? notes = noteCount != null
        ? '$noteCount notes'
        : countFailed
            ? l10n(context).countUnavailable
            : null;
    final folders =
        folderCount != null && folderCount! > 0 ? '$folderCount folders' : null;

    return [folders, notes].whereType<String>().join(' • ');
  }
}
