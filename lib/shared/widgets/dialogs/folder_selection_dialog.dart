import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';

import '../../../core/sync/models/folder_model.dart';
import '../../../core/sync/providers/sync_providers.dart';
import '../../../core/sync/repositories/folder_repository.dart';
import 'delete_folder_dialog.dart';
import 'rename_folder_dialog.dart';
import '../../../features/notes/presentation/providers/database_provider.dart';
import '../skeletons/skeletons.dart';

/// Dialog result containing the selected folder ID (null for root/no folder)
class FolderSelectionResult {
  final String? folderId;
  final String? folderName;

  const FolderSelectionResult({this.folderId, this.folderName});
}

/// Dialog for selecting a folder before creating a new note
/// Also provides folder management (create, rename, delete folders)
class FolderSelectionDialog extends ConsumerStatefulWidget {
  final String folderType;

  const FolderSelectionDialog({super.key, this.folderType = 'note'});

  /// Shows the folder selection dialog and returns the selected folder
  /// Returns null if the dialog was dismissed, or FolderSelectionResult with the selection
  static Future<FolderSelectionResult?> show(
    BuildContext context, {
    String folderType = 'note',
  }) {
    return showDialog<FolderSelectionResult>(
      context: context,
      builder: (context) => FolderSelectionDialog(folderType: folderType),
    );
  }

  @override
  ConsumerState<FolderSelectionDialog> createState() =>
      _FolderSelectionDialogState();
}

class _FolderSelectionDialogState extends ConsumerState<FolderSelectionDialog> {
  String? _selectedFolderId;
  bool _isCreatingFolder = false;
  String? _creatingInFolderId; // Parent folder for new folder creation
  final _newFolderController = TextEditingController();
  final _newFolderFocusNode = FocusNode();

  // Track expanded folders for hierarchical view
  final Set<String> _expandedFolders = {};

  bool get _isSongType => widget.folderType == 'song';
  Color get _accentColor => _isSongType ? AppTheme.orange : AppTheme.brandPurple;
  String get _entityLabel => _isSongType ? 'Songbook' : 'Folder';
  String get _entityLabelLower => _isSongType ? 'songbook' : 'folder';
  String get _contentLabel => _isSongType ? 'Song' : 'Note';
  String get _contentLabelLower => _isSongType ? 'song' : 'note';

  @override
  void dispose() {
    _newFolderController.dispose();
    _newFolderFocusNode.dispose();
    super.dispose();
  }

  StreamProvider<List<FolderModel>> get _foldersProvider =>
      widget.folderType == 'song'
          ? songFoldersStreamProvider
          : noteFoldersStreamProvider;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foldersAsync = ref.watch(_foldersProvider);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400, maxHeight: 550),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _accentColor.withValues(alpha: 0.1),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _isSongType ? Icons.library_books_outlined : Icons.folder_outlined,
                    color: _accentColor,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Select $_entityLabel',
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

            // Folder list
            Flexible(
              child: foldersAsync.when(
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: ListTileSkeletonList(count: 4, hasLeading: false),
                ),
                error: (e, _) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text('Error loading folders: $e'),
                  ),
                ),
                data: (folders) => _buildFolderList(context, folders),
              ),
            ),

            // Create new folder section
            if (_isCreatingFolder) _buildNewFolderInput(context),

            // Actions
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: Colors.grey.shade200),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Add folder button (top row, optional)
                  if (!_isCreatingFolder)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.create_new_folder_outlined, size: 18),
                        label: Text('New $_entityLabel'),
                        onPressed: () => _startCreatingFolder(null),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _accentColor,
                          side: BorderSide(color: _accentColor.withValues(alpha: 0.3)),
                        ),
                      ),
                    ),
                  // Action buttons row
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.grey.shade700,
                          ),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: _confirmSelection,
                          style: FilledButton.styleFrom(
                            backgroundColor: _accentColor,
                          ),
                          child: Text('Create $_contentLabel'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFolderList(BuildContext context, List<FolderModel> folders) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Build hierarchical list
    final rootFolders = folders.where((f) => f.parentId == null).toList();
    rootFolders.sort((a, b) => a.name.compareTo(b.name));

    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        // "No Folder/Songbook" option (root level)
        _FolderTile(
          icon: _isSongType ? Icons.music_note_outlined : Icons.notes_outlined,
          title: 'No $_entityLabel',
          subtitle: 'Create $_contentLabelLower at root level',
          isSelected: _selectedFolderId == null,
          accentColor: _accentColor,
          depth: 0,
          onTap: () {
            setState(() {
              _selectedFolderId = null;
            });
          },
        ),

        if (folders.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              _isSongType ? 'SONGBOOKS' : 'FOLDERS',
              style: theme.textTheme.labelSmall?.copyWith(
                color: Colors.grey,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
          ),
          // Build hierarchical folder tree
          ...rootFolders.expand((folder) => _buildFolderTree(
                context,
                folder,
                folders,
                depth: 0,
              )),
        ],

        if (folders.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Icon(
                  Icons.folder_open_outlined,
                  size: 48,
                  color: colorScheme.onSurface.withValues(alpha: 0.3),
                ),
                const SizedBox(height: 8),
                Text(
                  'No ${_entityLabelLower}s yet',
                  style: TextStyle(color: Colors.grey.shade600),
                ),
                const SizedBox(height: 4),
                Text(
                  'Create a $_entityLabelLower to organize your ${_contentLabelLower}s',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.grey.shade400,
                  ),
                ),
              ],
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

    final widgets = <Widget>[
      _FolderTile(
        icon: hasChildren
            ? (isExpanded ? Icons.folder_open_outlined : Icons.folder_outlined)
            : Icons.folder_outlined,
        title: folder.name,
        isSelected: isSelected,
        accentColor: _accentColor,
        depth: depth,
        hasChildren: hasChildren,
        isExpanded: isExpanded,
        visibility: folder.visibility,
        onTap: () {
          setState(() {
            _selectedFolderId = folder.id;
          });
        },
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
        onAddSubfolder: () => _startCreatingFolder(folder.id),
        onRename: () => _showRenameFolderDialog(folder),
        onDelete: () => _showDeleteFolderDialog(folder, allFolders),
      ),
    ];

    // Add children if expanded
    if (isExpanded && hasChildren) {
      for (final child in children) {
        widgets.addAll(_buildFolderTree(
          context,
          child,
          allFolders,
          depth: depth + 1,
        ));
      }
    }

    return widgets;
  }

  Widget _buildNewFolderInput(BuildContext context) {
    final foldersAsync = ref.watch(_foldersProvider);
    final folders = foldersAsync.valueOrNull ?? [];

    // Get parent folder name if creating subfolder
    String? parentName;
    if (_creatingInFolderId != null) {
      final parent = folders.where((f) => f.id == _creatingInFolderId).firstOrNull;
      parentName = parent?.name;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _accentColor.withValues(alpha: 0.05),
        border: Border(
          top: BorderSide(color: Colors.grey.shade200),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (parentName != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'Creating $_entityLabelLower in "$parentName"',
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 12,
                ),
              ),
            ),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _newFolderController,
                  focusNode: _newFolderFocusNode,
                  decoration: InputDecoration(
                    hintText: '$_entityLabel name',
                    prefixIcon: Icon(Icons.folder_outlined, color: Colors.grey.shade400, size: 20),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(
                        color: _accentColor.withValues(alpha: 0.3),
                        width: 1.0,
                      ),
                    ),
                    hintStyle: TextStyle(
                      fontSize: 15,
                      color: Colors.grey.shade400,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                  ),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                  textCapitalization: TextCapitalization.words,
                  onSubmitted: (_) => _createFolder(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.check),
                onPressed: _createFolder,
                style: IconButton.styleFrom(
                  backgroundColor: _accentColor,
                  foregroundColor: Colors.white,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: _cancelCreatingFolder,
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _startCreatingFolder(String? parentId) {
    setState(() {
      _isCreatingFolder = true;
      _creatingInFolderId = parentId;
      // Expand parent folder if creating subfolder
      if (parentId != null) {
        _expandedFolders.add(parentId);
      }
    });
    // Focus the text field after the next frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _newFolderFocusNode.requestFocus();
    });
  }

  void _cancelCreatingFolder() {
    setState(() {
      _isCreatingFolder = false;
      _creatingInFolderId = null;
      _newFolderController.clear();
    });
  }

  Future<void> _createFolder() async {
    final name = _newFolderController.text.trim();
    if (name.isEmpty) return;

    try {
      final repository = ref.read(folderRepositoryProvider);
      final userId = ref.read(currentUserIdProvider);

      final folder = await repository.createFolder(
        name: name,
        userId: userId,
        parentId: _creatingInFolderId,
        type: widget.folderType,
      );

      // Select the newly created folder
      setState(() {
        _selectedFolderId = folder.id;
        _isCreatingFolder = false;
        _creatingInFolderId = null;
        _newFolderController.clear();
      });
    } on FolderNameConflictException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('A $_entityLabelLower with this name already exists'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to create $_entityLabelLower: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _showRenameFolderDialog(FolderModel folder) async {
    await RenameFolderDialog.show(context, folder);
  }

  Future<void> _showDeleteFolderDialog(
    FolderModel folder,
    List<FolderModel> allFolders,
  ) async {
    // Count notes in folder
    final notesRepository = ref.read(notesRepositoryProvider);
    final noteCount = await notesRepository.getNoteCountInFolder(folder.id);

    // Count subfolders
    final descendants = _getDescendants(folder.id, allFolders);

    if (!mounted) return;

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
    String folderId,
    List<FolderModel> allFolders,
  ) {
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

      // Delete the folder (this will cascade delete descendants)
      await folderRepository.deleteFolder(folder.id);

      // Clear selection if deleted folder was selected
      if (_selectedFolderId == folder.id ||
          descendants.any((d) => d.id == _selectedFolderId)) {
        setState(() {
          _selectedFolderId = null;
        });
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$_entityLabel deleted, ${_contentLabelLower}s moved to root'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error deleting $_entityLabelLower: $e'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.red,
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
    final notesRepository = ref.read(notesRepositoryProvider);

    try {
      // Delete notes from this folder and all descendants
      await notesRepository.deleteNotesInFolder(folder.id);
      for (final descendant in descendants) {
        await notesRepository.deleteNotesInFolder(descendant.id);
      }

      // Delete the folder (this will cascade delete descendants)
      await folderRepository.deleteFolder(folder.id);

      // Clear selection if deleted folder was selected
      if (_selectedFolderId == folder.id ||
          descendants.any((d) => d.id == _selectedFolderId)) {
        setState(() {
          _selectedFolderId = null;
        });
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$_entityLabel and ${_contentLabelLower}s deleted'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error deleting $_entityLabelLower: $e'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _confirmSelection() {
    final folders = ref.read(_foldersProvider).valueOrNull ?? [];
    String? folderName;

    if (_selectedFolderId != null) {
      final folder = folders.where((f) => f.id == _selectedFolderId).firstOrNull;
      folderName = folder?.name;
    }

    Navigator.of(context).pop(FolderSelectionResult(
      folderId: _selectedFolderId,
      folderName: folderName,
    ));
  }
}

class _FolderTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final bool isSelected;
  final int depth;
  final bool hasChildren;
  final bool isExpanded;
  final FolderVisibility? visibility;
  final Color accentColor;
  final VoidCallback onTap;
  final VoidCallback? onExpandToggle;
  final VoidCallback? onAddSubfolder;
  final VoidCallback? onRename;
  final VoidCallback? onDelete;

  const _FolderTile({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.isSelected,
    required this.depth,
    this.hasChildren = false,
    this.isExpanded = false,
    this.visibility,
    required this.accentColor,
    required this.onTap,
    this.onExpandToggle,
    this.onAddSubfolder,
    this.onRename,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final hasActions = onAddSubfolder != null || onRename != null || onDelete != null;

    return Material(
      color: isSelected
          ? accentColor.withValues(alpha: 0.1)
          : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.only(
            left: 16.0 + (depth * 20.0),
            right: 8,
            top: 8,
            bottom: 8,
          ),
          child: Row(
            children: [
              // Expand/collapse button for folders with children
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
                const SizedBox(width: 22), // Alignment spacer
              Icon(
                icon,
                color: isSelected ? accentColor : Colors.grey,
                size: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                              color: isSelected ? accentColor : null,
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
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.grey,
                        ),
                      ),
                  ],
                ),
              ),
              if (isSelected)
                Icon(
                  Icons.check_circle,
                  color: accentColor,
                  size: 20,
                ),
              if (hasActions)
                PopupMenuButton<String>(
                  icon: Icon(
                    Icons.more_vert,
                    size: 18,
                    color: colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                  padding: EdgeInsets.zero,
                  onSelected: (value) {
                    switch (value) {
                      case 'add_subfolder':
                        onAddSubfolder?.call();
                        break;
                      case 'rename':
                        onRename?.call();
                        break;
                      case 'delete':
                        onDelete?.call();
                        break;
                    }
                  },
                  itemBuilder: (context) => [
                    if (onAddSubfolder != null)
                      const PopupMenuItem(
                        value: 'add_subfolder',
                        child: Row(
                          children: [
                            Icon(Icons.create_new_folder_outlined, size: 18),
                            SizedBox(width: 8),
                            Text('Add subfolder'),
                          ],
                        ),
                      ),
                    if (onRename != null)
                      const PopupMenuItem(
                        value: 'rename',
                        child: Row(
                          children: [
                            Icon(Icons.edit_outlined, size: 18),
                            SizedBox(width: 8),
                            Text('Rename'),
                          ],
                        ),
                      ),
                    if (onDelete != null) ...[
                      const PopupMenuDivider(),
                      PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete_outline, size: 18, color: Colors.red),
                            const SizedBox(width: 8),
                            const Text('Delete', style: TextStyle(color: Colors.red)),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
