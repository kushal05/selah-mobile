import 'package:flutter/material.dart';

import '../../../core/sync/models/folder_model.dart';

/// Options for what to do with notes when deleting a folder
enum DeleteFolderOption {
  moveToRoot,
  deleteAll,
}

/// Dialog for confirming folder deletion with options for handling notes
class DeleteFolderDialog extends StatefulWidget {
  final FolderModel folder;
  final int noteCount;
  final int subfolderCount;
  final VoidCallback onMoveNotesToRoot;
  final VoidCallback onDeleteAll;

  const DeleteFolderDialog({
    super.key,
    required this.folder,
    required this.noteCount,
    required this.subfolderCount,
    required this.onMoveNotesToRoot,
    required this.onDeleteAll,
  });

  /// Shows the delete folder dialog
  static Future<void> show(
    BuildContext context, {
    required FolderModel folder,
    required int noteCount,
    required int subfolderCount,
    required VoidCallback onMoveNotesToRoot,
    required VoidCallback onDeleteAll,
  }) {
    return showDialog<void>(
      context: context,
      builder: (context) => DeleteFolderDialog(
        folder: folder,
        noteCount: noteCount,
        subfolderCount: subfolderCount,
        onMoveNotesToRoot: onMoveNotesToRoot,
        onDeleteAll: onDeleteAll,
      ),
    );
  }

  @override
  State<DeleteFolderDialog> createState() => _DeleteFolderDialogState();
}

class _DeleteFolderDialogState extends State<DeleteFolderDialog> {
  DeleteFolderOption _selectedOption = DeleteFolderOption.moveToRoot;

  bool get _hasContent => widget.noteCount > 0 || widget.subfolderCount > 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: Colors.orange.shade700),
          const SizedBox(width: 12),
          const Expanded(child: Text('Delete Folder')),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Are you sure you want to delete "${widget.folder.name}"?',
            style: theme.textTheme.bodyLarge,
          ),
          if (_hasContent) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.errorContainer.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: colorScheme.error.withValues(alpha: 0.3),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 18,
                        color: colorScheme.error,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'This folder contains:',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (widget.noteCount > 0)
                    Text(
                      '  \u2022 ${widget.noteCount} note${widget.noteCount == 1 ? '' : 's'}',
                      style: theme.textTheme.bodyMedium,
                    ),
                  if (widget.subfolderCount > 0)
                    Text(
                      '  \u2022 ${widget.subfolderCount} subfolder${widget.subfolderCount == 1 ? '' : 's'}',
                      style: theme.textTheme.bodyMedium,
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'What would you like to do with the notes?',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            RadioGroup<DeleteFolderOption>(
              groupValue: _selectedOption,
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _selectedOption = value;
                  });
                }
              },
              child: Column(
                children: [
                  _buildOptionTile(
                    context,
                    option: DeleteFolderOption.moveToRoot,
                    icon: Icons.drive_file_move_outline,
                    title: 'Move notes to root',
                    subtitle: 'Notes will be moved to the top level',
                  ),
                  const SizedBox(height: 8),
                  _buildOptionTile(
                    context,
                    option: DeleteFolderOption.deleteAll,
                    icon: Icons.delete_forever_outlined,
                    title: 'Delete everything',
                    subtitle: 'Notes and subfolders will be permanently deleted',
                    isDestructive: true,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.of(context).pop();
            if (_selectedOption == DeleteFolderOption.moveToRoot) {
              widget.onMoveNotesToRoot();
            } else {
              widget.onDeleteAll();
            }
          },
          style: FilledButton.styleFrom(
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
          ),
          child: Text(_hasContent ? 'Delete' : 'Delete Folder'),
        ),
      ],
    );
  }

  Widget _buildOptionTile(
    BuildContext context, {
    required DeleteFolderOption option,
    required IconData icon,
    required String title,
    required String subtitle,
    bool isDestructive = false,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isSelected = _selectedOption == option;

    return Material(
      color: isSelected
          ? (isDestructive
              ? Colors.red.withValues(alpha: 0.1)
              : colorScheme.primaryContainer.withValues(alpha: 0.3))
          : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: () {
          setState(() {
            _selectedOption = option;
          });
        },
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected
                  ? (isDestructive ? Colors.red : colorScheme.primary)
                  : Colors.grey.shade300,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Radio<DeleteFolderOption>(
                value: option,
                activeColor: isDestructive ? Colors.red : colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Icon(
                icon,
                color: isDestructive ? Colors.red : colorScheme.primary,
                size: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: isDestructive ? Colors.red : null,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
