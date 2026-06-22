import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../drag_handle.dart';

import '../../../core/sync/models/folder_model.dart';
import '../../../core/sync/providers/sync_providers.dart';
import '../skeletons/skeletons.dart';

/// Result returned by [MoveToFolderSheet] when the user confirms a move.
class MoveToFolderResult {
  final String targetFolderId;
  final String targetFolderName;

  const MoveToFolderResult({
    required this.targetFolderId,
    required this.targetFolderName,
  });
}

/// Modal bottom sheet for picking a destination folder when moving notes.
///
/// Shows the folder hierarchy as a tree. The current folder is disabled.
/// Deleted folders are excluded automatically (foldersStreamProvider filters them).
class MoveToFolderSheet extends ConsumerStatefulWidget {
  /// The folder ID that should be disabled (the current folder of the note).
  /// Pass null if the notes are at root level.
  final String? currentFolderId;

  /// Additional folder IDs to disable (e.g. descendants when moving a folder).
  final Set<String> disabledFolderIds;

  /// How many notes are being moved (for the header label).
  final int noteCount;

  /// Custom header title. If null, defaults to "Move Note" / "Move N Notes".
  final String? headerTitle;

  const MoveToFolderSheet({
    super.key,
    this.currentFolderId,
    this.disabledFolderIds = const {},
    this.noteCount = 1,
    this.headerTitle,
  });

  /// Shows the sheet and returns the selected folder, or null if cancelled.
  static Future<MoveToFolderResult?> show(
    BuildContext context, {
    String? currentFolderId,
    Set<String> disabledFolderIds = const {},
    int noteCount = 1,
    String? headerTitle,
  }) {
    return showModalBottomSheet<MoveToFolderResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => MoveToFolderSheet(
        currentFolderId: currentFolderId,
        disabledFolderIds: disabledFolderIds,
        noteCount: noteCount,
        headerTitle: headerTitle,
      ),
    );
  }

  @override
  ConsumerState<MoveToFolderSheet> createState() => _MoveToFolderSheetState();
}

class _MoveToFolderSheetState extends ConsumerState<MoveToFolderSheet> {
  String? _selectedFolderId;
  final Set<String> _expandedFolders = {};

  bool get _hasSelection => _selectedFolderId != null;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foldersAsync = ref.watch(foldersStreamProvider);

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            const DragHandle(),

            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  const Icon(
                    Icons.drive_file_move_outlined,
                    color: AppTheme.brandPurple,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.headerTitle ??
                          (widget.noteCount == 1
                              ? 'Move Note'
                              : 'Move ${widget.noteCount} Notes'),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),

            Divider(height: 1, color: Colors.grey.shade200),

            // Folder list
            Expanded(
              child: foldersAsync.when(
                loading: () => const ListTileSkeletonList(count: 4, hasLeading: false),
                error: (e, _) => Center(child: Text('Error loading folders: $e')),
                data: (folders) =>
                    _buildFolderList(context, folders, scrollController),
              ),
            ),

            // Confirm button
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: Colors.grey.shade200)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _hasSelection ? _confirmMove : null,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.brandPurple,
                      ),
                      child: const Text('Move Here'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildFolderList(
    BuildContext context,
    List<FolderModel> folders,
    ScrollController scrollController,
  ) {
    final theme = Theme.of(context);
    final rootFolders = folders.where((f) => f.parentId == null).toList();
    rootFolders.sort((a, b) => a.name.compareTo(b.name));

    final isCurrent = widget.currentFolderId == 'root';

    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        // "No Folder" / root option
        _MoveTargetTile(
          icon: Icons.notes_outlined,
          title: 'No Folder',
          subtitle: 'Root level',
          depth: 0,
          isSelected: _selectedFolderId == 'root',
          isDisabled: isCurrent,
          onTap: isCurrent
              ? null
              : () => setState(() => _selectedFolderId = 'root'),
        ),

        if (folders.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              'FOLDERS',
              style: theme.textTheme.labelSmall?.copyWith(
                color: Colors.grey,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
          ),
          ...rootFolders.expand(
            (folder) => _buildFolderTree(context, folder, folders, depth: 0),
          ),
        ],

        if (folders.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: Text(
                'No folders available',
                style: TextStyle(color: Colors.grey.shade500),
              ),
            ),
          ),
      ],
    );
  }

  List<Widget> _buildFolderTree(
    BuildContext context,
    FolderModel folder,
    List<FolderModel> allFolders, {
    required int depth,
  }) {
    final children = allFolders.where((f) => f.parentId == folder.id).toList();
    children.sort((a, b) => a.name.compareTo(b.name));
    final hasChildren = children.isNotEmpty;
    final isExpanded = _expandedFolders.contains(folder.id);
    final isSelected = _selectedFolderId == folder.id;
    final isDisabled = folder.id == widget.currentFolderId ||
        widget.disabledFolderIds.contains(folder.id);

    final widgets = <Widget>[
      _MoveTargetTile(
        icon: hasChildren
            ? (isExpanded ? Icons.folder_open_outlined : Icons.folder_outlined)
            : Icons.folder_outlined,
        title: folder.name,
        depth: depth,
        isSelected: isSelected,
        isDisabled: isDisabled,
        hasChildren: hasChildren,
        isExpanded: isExpanded,
        onTap: isDisabled
            ? null
            : () => setState(() => _selectedFolderId = folder.id),
        onExpandToggle: hasChildren
            ? () {
                setState(() {
                  if (isExpanded) {
                    _expandedFolders.remove(folder.id);
                  } else {
                    _expandedFolders.add(folder.id);
                  }
                });
              }
            : null,
      ),
    ];

    if (isExpanded && hasChildren) {
      for (final child in children) {
        widgets.addAll(
          _buildFolderTree(context, child, allFolders, depth: depth + 1),
        );
      }
    }

    return widgets;
  }

  void _confirmMove() {
    if (_selectedFolderId == null) return;

    final folders = ref.read(foldersStreamProvider).valueOrNull ?? [];
    String folderName;

    if (_selectedFolderId == 'root') {
      folderName = 'No Folder';
    } else {
      final folder =
          folders.where((f) => f.id == _selectedFolderId).firstOrNull;
      folderName = folder?.name ?? 'Unknown';
    }

    Navigator.of(context).pop(MoveToFolderResult(
      targetFolderId: _selectedFolderId!,
      targetFolderName: folderName,
    ));
  }
}

/// A single row in the folder tree for the move sheet.
class _MoveTargetTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final int depth;
  final bool isSelected;
  final bool isDisabled;
  final bool hasChildren;
  final bool isExpanded;
  final VoidCallback? onTap;
  final VoidCallback? onExpandToggle;

  const _MoveTargetTile({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.depth,
    required this.isSelected,
    this.isDisabled = false,
    this.hasChildren = false,
    this.isExpanded = false,
    this.onTap,
    this.onExpandToggle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final opacity = isDisabled ? 0.4 : 1.0;

    return Material(
      color: isSelected
          ? AppTheme.brandPurple.withValues(alpha: 0.1)
          : Colors.transparent,
      child: InkWell(
        onTap: isDisabled ? null : onTap,
        child: Padding(
          padding: EdgeInsets.only(
            left: 16.0 + (depth * 20.0),
            right: 16,
            top: 10,
            bottom: 10,
          ),
          child: Opacity(
            opacity: opacity,
            child: Row(
              children: [
                if (hasChildren)
                  GestureDetector(
                    onTap: onExpandToggle,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: AnimatedRotation(
                        turns: isExpanded ? 0.25 : 0,
                        duration: const Duration(milliseconds: 200),
                        child: Icon(
                          Icons.chevron_right_rounded,
                          size: 18,
                          color: colorScheme.onSurface.withValues(alpha: 0.5),
                        ),
                      ),
                    ),
                  )
                else if (depth > 0)
                  const SizedBox(width: 22),
                Icon(
                  icon,
                  color: isSelected ? AppTheme.brandPurple : Colors.grey,
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
                          fontWeight:
                              isSelected ? FontWeight.w600 : FontWeight.normal,
                          color: isSelected ? AppTheme.brandPurple : null,
                        ),
                      ),
                      if (subtitle != null)
                        Text(
                          subtitle!,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: Colors.grey),
                        ),
                      if (isDisabled)
                        Text(
                          'Current folder',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: Colors.grey),
                        ),
                    ],
                  ),
                ),
                if (isSelected)
                  const Icon(
                    Icons.check_circle,
                    color: AppTheme.brandPurple,
                    size: 20,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
