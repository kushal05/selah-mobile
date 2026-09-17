import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/drag_handle.dart';
import '../../../../core/sync/models/folder_model.dart';
import '../../../../core/sync/providers/sync_providers.dart';
import '../providers/database_provider.dart';
import '../../../../shared/widgets/dialogs/create_folder_dialog.dart';
import '../../../../shared/widgets/dialogs/delete_folder_dialog.dart';
import '../../../../shared/widgets/dialogs/move_to_folder_sheet.dart';
import '../../../../shared/widgets/dialogs/rename_folder_dialog.dart';
import '../../../../shared/widgets/skeletons/skeletons.dart';
import '../../../../core/services/user_facing_error.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../../../core/providers/motion_preferences.dart';
import '../../../../core/theme/theme_colors.dart';
import '../../../../l10n/l10n.dart';

/// Screen for managing folders - create, rename, delete, and organize
class FolderManagementScreen extends ConsumerStatefulWidget {
  const FolderManagementScreen({super.key});

  @override
  ConsumerState<FolderManagementScreen> createState() =>
      _FolderManagementScreenState();
}

class _FolderManagementScreenState
    extends ConsumerState<FolderManagementScreen> {
  // Track expanded folders
  final Set<String> _expandedFolders = {};

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final foldersAsync = ref.watch(foldersStreamProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n(context).manageFolders),
        backgroundColor: colorScheme.surface,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded),
            tooltip: l10n(context).trash,
            onPressed: () => _showTrashSheet(context),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showCreateFolderDialog(context, null),
        backgroundColor: AppTheme.brandPurple,
        foregroundColor: AppTheme.onAccent(AppTheme.brandPurple),
        child: const Icon(Icons.create_new_folder_rounded),
      ),
      body: foldersAsync.when(
        loading: () => const ListTileSkeletonList(count: 5, hasLeading: false),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: colorScheme.error),
              const SizedBox(height: 16),
              Text(UserFacingError.forLoad(e)),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => ref.invalidate(foldersStreamProvider),
                child: Text(l10n(context).retry),
              ),
            ],
          ),
        ),
        data: (folders) {
          if (folders.isEmpty) {
            return _buildEmptyState(context);
          }
          return _buildFolderTree(context, folders);
        },
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return EmptyState(
      icon: Icons.folder_open_rounded,
      title: l10n(context).noFoldersYet,
      message: l10n(context).foldersGroupRelatedNotesTogetherOnePerSeries,
      accent: AppTheme.brandPurple,
    );
  }

  Widget _buildFolderTree(BuildContext context, List<FolderModel> allFolders) {
    // Build a tree structure from flat list
    final rootFolders =
        allFolders.where((f) => f.parentId == null).toList();

    // Sort alphabetically
    rootFolders.sort((a, b) => a.name.compareTo(b.name));

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 80),
      itemCount: rootFolders.length,
      itemBuilder: (context, index) {
        return _buildFolderItem(
          context,
          rootFolders[index],
          allFolders,
          depth: 0,
        );
      },
    );
  }

  Widget _buildFolderItem(
    BuildContext context,
    FolderModel folder,
    List<FolderModel> allFolders, {
    required int depth,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Get children of this folder
    final children =
        allFolders.where((f) => f.parentId == folder.id).toList();
    children.sort((a, b) => a.name.compareTo(b.name));

    final hasChildren = children.isNotEmpty;
    final isExpanded = _expandedFolders.contains(folder.id);

    // Get note count for this folder
    final noteCountAsync = ref.watch(noteCountInFolderProvider(folder.id));
    final noteCount = noteCountAsync.when(
      data: (count) => count,
      loading: () => 0,
      error: (_, _) => 0,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: hasChildren
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
            child: Padding(
              padding: EdgeInsets.only(
                left: 16.0 + (depth * 24.0),
                right: 8,
                top: 4,
                bottom: 4,
              ),
              child: Row(
                children: [
                  // Expand/collapse indicator
                  SizedBox(
                    width: 24,
                    child: hasChildren
                        ? IconButton(
                          tooltip: isExpanded ? 'Collapse folder' : 'Expand folder',
                            icon: AnimatedRotation(
                              turns: isExpanded ? 0.25 : 0,
                              duration: context.motion(const Duration(milliseconds: 200)),
                              child: Icon(
                                Icons.chevron_right_rounded,
                                size: 20,
                                color: colorScheme.onSurface.withValues(alpha: 0.5),
                              ),
                            ),
                            onPressed: () {
                              setState(() {
                                if (isExpanded) {
                                  _expandedFolders.remove(folder.id);
                                } else {
                                  _expandedFolders.add(folder.id);
                                }
                              });
                            },
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            visualDensity: VisualDensity.compact,
                          )
                        : null,
                  ),
                  const SizedBox(width: 8),
                  // Folder icon
                  Icon(
                    isExpanded
                        ? Icons.folder_open_rounded
                        : Icons.folder_rounded,
                    color: AppTheme.brandPurple,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  // Folder name and note count
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          folder.name,
                          style: theme.textTheme.bodyLarge,
                        ),
                        Text(
                          '$noteCount notes${hasChildren ? ' • ${children.length} subfolders' : ''}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: context.mutedText,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Action menu
                  PopupMenuButton<String>(
                    icon: Icon(
                      Icons.more_vert_rounded,
                      color: colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                    onSelected: (value) =>
                        _handleFolderAction(context, folder, value, allFolders),
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'add_subfolder',
                        child: Row(
                          children: [
                            Icon(Icons.create_new_folder_outlined, size: 20),
                            SizedBox(width: 12),
                            Text(l10n(context).addSubfolder),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'rename',
                        child: Row(
                          children: [
                            Icon(Icons.edit_outlined, size: 20),
                            SizedBox(width: 12),
                            Text(l10n(context).rename),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'move',
                        child: Row(
                          children: [
                            Icon(Icons.drive_file_move_outlined, size: 20),
                            SizedBox(width: 12),
                            Text(l10n(context).move),
                          ],
                        ),
                      ),
                      const PopupMenuDivider(),
                      PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete_outline,
                                size: 20, color: context.dangerText),
                            const SizedBox(width: 12),
                            Text(l10n(context).moveToTrash,
                                style: TextStyle(color: context.dangerText)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        // Show children if expanded
        if (isExpanded && hasChildren)
          ...children.map((child) => _buildFolderItem(
                context,
                child,
                allFolders,
                depth: depth + 1,
              )),
      ],
    );
  }

  void _handleFolderAction(
    BuildContext context,
    FolderModel folder,
    String action,
    List<FolderModel> allFolders,
  ) {
    switch (action) {
      case 'add_subfolder':
        _showCreateFolderDialog(context, folder.id);
        break;
      case 'rename':
        _showRenameFolderDialog(context, folder);
        break;
      case 'move':
        _showMoveFolderSheet(context, folder, allFolders);
        break;
      case 'delete':
        _showDeleteFolderDialog(context, folder, allFolders);
        break;
    }
  }

  Future<void> _showCreateFolderDialog(
      BuildContext context, String? parentId) async {
    final result = await CreateFolderDialog.show(context, parentId: parentId);
    if (result == true && parentId != null && mounted) {
      // Expand parent folder to show new subfolder
      setState(() {
        _expandedFolders.add(parentId);
      });
    }
  }

  Future<void> _showRenameFolderDialog(
      BuildContext context, FolderModel folder) async {
    await RenameFolderDialog.show(context, folder);
  }

  Future<void> _showMoveFolderSheet(
    BuildContext context,
    FolderModel folder,
    List<FolderModel> allFolders,
  ) async {
    // Disable the folder itself and all its descendants to prevent circular moves
    final descendants = _getDescendants(folder.id, allFolders);
    final disabledIds = {folder.id, ...descendants.map((d) => d.id)};

    // Current parent (or 'root' if at root level) so the no-op option is disabled
    final currentParentId = folder.parentId ?? 'root';

    final result = await MoveToFolderSheet.show(
      context,
      currentFolderId: currentParentId,
      disabledFolderIds: disabledIds,
      headerTitle: 'Move Folder',
    );

    if (result == null || !context.mounted) return;

    final folderRepository = ref.read(folderRepositoryProvider);

    try {
      final newParentId =
          result.targetFolderId == 'root' ? null : result.targetFolderId;
      await folderRepository.updateFolder(
        id: folder.id,
        parentId: newParentId,
        clearParent: newParentId == null,
      );

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text(l10n(context).movedFolderToTarget(folder.name, result.targetFolderName)),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(UserFacingError.message(e, action: 'move that folder')),
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppTheme.errorSurface,
          ),
        );
      }
    }
  }

  Future<void> _showDeleteFolderDialog(
    BuildContext context,
    FolderModel folder,
    List<FolderModel> allFolders,
  ) async {
    // Count notes and subfolders
    final noteCountAsync = ref.read(noteCountInFolderProvider(folder.id));
    final noteCount = noteCountAsync.when(
      data: (count) => count,
      loading: () => 0,
      error: (_, _) => 0,
    );

    // Get all descendant folders
    final descendants = _getDescendants(folder.id, allFolders);

    await DeleteFolderDialog.show(
      context,
      folder: folder,
      noteCount: noteCount,
      subfolderCount: descendants.length,
      onMoveNotesToRoot: () => _deleteFolderAndMoveNotes(folder, descendants),
      onDeleteAll: () => _deleteFolderAndNotes(folder, descendants),
    );
  }

  List<FolderModel> _getDescendants(
      String folderId, List<FolderModel> allFolders) {
    final result = <FolderModel>[];
    final children = allFolders.where((f) => f.parentId == folderId).toList();
    for (final child in children) {
      result.add(child);
      result.addAll(_getDescendants(child.id, allFolders));
    }
    return result;
  }

  Future<void> _deleteFolderAndMoveNotes(
    FolderModel folder,
    List<FolderModel> descendants,
  ) async {
    final folderRepository = ref.read(folderRepositoryProvider);
    final notesRepository = ref.read(notesRepositoryProvider);

    try {
      // Move notes from this folder and all descendants to root
      await notesRepository.moveNotesFromFolder(folder.id, null);
      for (final descendant in descendants) {
        await notesRepository.moveNotesFromFolder(descendant.id, null);
      }

      // Trash the folder (this will cascade trash descendants)
      await folderRepository.trashFolder(folder.id);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n(context).folderMovedToTrashNotesMovedToRoot),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(UserFacingError.message(e, action: 'move that folder to Trash')),
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppTheme.errorSurface,
          ),
        );
      }
    }
  }

  Future<void> _deleteFolderAndNotes(
    FolderModel folder,
    List<FolderModel> descendants,
  ) async {
    final folderRepository = ref.read(folderRepositoryProvider);

    try {
      // Trash the folder (cascades to notes and descendants)
      await folderRepository.trashFolder(folder.id);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n(context).folderAndNotesMovedToTrash),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(UserFacingError.message(e, action: 'move that folder to Trash')),
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppTheme.errorSurface,
          ),
        );
      }
    }
  }

  void _showTrashSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => const _TrashFoldersSheet(),
    );
  }
}

/// Bottom sheet listing soft-deleted folders with restore action.
class _TrashFoldersSheet extends ConsumerWidget {
  const _TrashFoldersSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final deletedAsync = ref.watch(deletedNoteFoldersProvider);

    return SafeArea(
      // Keeps the sheet's last control clear of the gesture bar.
      top: false,
      child: DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.85,
        expand: false,
        builder: (context, scrollController) {
          return Column(
            children: [
              const DragHandle(),
              // Header
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    const Icon(Icons.delete_outline_rounded,
                        color: AppTheme.brandPurple),
                    const SizedBox(width: 12),
                    Text(
                      l10n(context).deletedFolders,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: l10n(context).close,
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: context.hairline),
              // List
              Expanded(
                child: deletedAsync.when(
                  loading: () =>
                      const ListTileSkeletonList(count: 3, hasLeading: false),
                  error: (e, _) => Center(child: Text(UserFacingError.forLoad(e))),
                  data: (folders) {
                    if (folders.isEmpty) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.check_circle_outline,
                                  size: 48,
                                  color: context.hintText),
                              const SizedBox(height: 12),
                              Text(l10n(context).trashEmptyTitle,
                                  style: theme.textTheme.bodyLarge
                                      ?.copyWith(color: context.mutedText)),
                            ],
                          ),
                        ),
                      );
                    }
                    return ListView.separated(
                      controller: scrollController,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: folders.length,
                      separatorBuilder: (_, _) =>
                          Divider(height: 1, indent: 16, color: context.hairline),
                      itemBuilder: (context, index) {
                        final folder = folders[index];
                        final deletedDate = DateTime.fromMillisecondsSinceEpoch(
                            folder.updatedAt);
                        return ListTile(
                          leading: Icon(Icons.folder_outlined,
                              color: context.mutedText),
                          title: Text(folder.name),
                          subtitle: Text(
                            'Deleted ${_formatDate(deletedDate)}',
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: context.mutedText),
                          ),
                          trailing: TextButton.icon(
                            icon: const Icon(Icons.restore, size: 18),
                            label: Text(l10n(context).restore),
                            style: TextButton.styleFrom(
                              foregroundColor: AppTheme.brandPurple,
                            ),
                            onPressed: () =>
                                _restoreFolder(context, ref, folder),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _restoreFolder(
      BuildContext context, WidgetRef ref, FolderModel folder) async {
    final folderRepository = ref.read(folderRepositoryProvider);
    try {
      await folderRepository.restoreFolder(folder.id);
      ref.invalidate(deletedNoteFoldersProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n(context).restoredNamed(folder.name)),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(UserFacingError.message(e, action: 'restore that folder')),
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppTheme.errorSurface,
          ),
        );
      }
    }
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inDays == 0) return 'today';
    if (diff.inDays == 1) return 'yesterday';
    if (diff.inDays < 7) return '${diff.inDays} days ago';
    return '${date.day}/${date.month}/${date.year}';
  }
}
