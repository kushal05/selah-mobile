import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:go_router/go_router.dart';

import '../../domain/models/block_type.dart';
import '../../domain/models/note_section.dart';
import '../../domain/models/note_table.dart';
import '../../../bible/domain/models/bible_reference.dart';
import '../../../../core/navigation/routes.dart';
import '../../../../core/sync/models/note_model.dart';
import '../../../../core/sync/providers/sync_providers.dart';
import '../../domain/models/note.dart' as domain;
import '../providers/database_provider.dart';
import '../../../../shared/widgets/lists/folder_row.dart';
import '../../../../shared/widgets/dialogs/folder_selection_dialog.dart';
import '../../../../shared/widgets/cards/note_row.dart';
import '../../../../shared/widgets/dialogs/move_to_folder_sheet.dart';
import '../widgets/note_template_picker_sheet.dart';
import 'folder_management_screen.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/skeletons/skeletons.dart';

/// Sort options for notes list
enum NotesSortOption {
  lastEdited('Last Edited'),
  title('Title (A-Z)'),
  createdDate('Created Date');

  final String label;
  const NotesSortOption(this.label);
}

/// Notes list screen showing folders and notes in a split layout
class NotesHomeScreen extends ConsumerStatefulWidget {
  const NotesHomeScreen({super.key});

  @override
  ConsumerState<NotesHomeScreen> createState() => _NotesHomeScreenState();
}

class _NotesHomeScreenState extends ConsumerState<NotesHomeScreen> {
  // Currently selected folder ID (null means "All Notes")
  String? _selectedFolderId;

  // Expanded folder IDs
  final Set<String> _expandedFolders = {};

  // Current sort option
  NotesSortOption _sortOption = NotesSortOption.lastEdited;
  bool _sortAscending = false;

  // Folder section collapsed state
  bool _isFolderSectionExpanded = false;

  // Multi-select state
  bool _isSelecting = false;
  final Set<String> _selectedNoteIds = {};

  // Smart collection state: which collection is active (null = none)
  String? _activeSmartCollection;

  // Trash view toggle
  bool _showingTrash = false;

  // Cache for note preview strings to avoid jsonDecode on every build.
  // Keyed by "${note.id}_${note.updatedAt}" so stale entries accumulate as
  // notes are edited. Cleared entirely once it exceeds the limit below to
  // prevent unbounded growth without the overhead of LRU bookkeeping.
  static const _previewCacheMaxSize = 500;
  final Map<String, String?> _previewCache = {};

  // Filter state
  bool _isFilterActive = true;
  final Set<String> _filterTagIds = {};
  String? _filterPreacherId;
  DateTimeRange? _filterDateRange;
  List<domain.Note>? _filteredNotes;

  bool get _hasActiveFilters =>
      _filterTagIds.isNotEmpty ||
      _filterPreacherId != null ||
      _filterDateRange != null;

  int get _activeFilterCount =>
      (_filterTagIds.isNotEmpty ? 1 : 0) +
      (_filterPreacherId != null ? 1 : 0) +
      (_filterDateRange != null ? 1 : 0);

  void _clearFilters() {
    setState(() {
      _filterTagIds.clear();
      _filterPreacherId = null;
      _filterDateRange = null;
      _isFilterActive = false;
      _filteredNotes = null;
    });
  }

  Future<void> _applyFilters() async {
    if (!_hasActiveFilters) {
      setState(() {
        _filteredNotes = null;
      });
      return;
    }

    try {
      final noteRepository = ref.read(noteRepositoryProvider);
      final userId = ref.read(currentUserIdProvider);

      final results = await noteRepository.searchNotesFiltered(
        userId: userId,
        tagIds: _filterTagIds.isNotEmpty ? _filterTagIds.toList() : null,
        preacherId: _filterPreacherId,
        dateFrom: _filterDateRange?.start.millisecondsSinceEpoch,
        dateTo: _filterDateRange?.end.add(const Duration(days: 1)).millisecondsSinceEpoch,
        folderId: _selectedFolderId,
      );

      // Convert NoteModel to domain Note using the existing provider's mapping
      final allNotes = ref.read(notesStreamProvider).valueOrNull ?? [];
      final filteredIds = results.map((n) => n.id).toSet();
      if (!mounted) return;
      setState(() {
        _filteredNotes = allNotes.where((n) => filteredIds.contains(n.id)).toList();
      });
    } catch (e) {
      debugPrint('Failed to apply filters: $e');
    }
  }

  void _toggleFolderSection() {
    setState(() {
      _isFolderSectionExpanded = !_isFolderSectionExpanded;
    });
  }

  void _enterSelectMode({String? initialNoteId}) {
    setState(() {
      _isSelecting = true;
      _selectedNoteIds.clear();
      if (initialNoteId != null) {
        _selectedNoteIds.add(initialNoteId);
      }
    });
  }

  void _exitSelectMode() {
    setState(() {
      _isSelecting = false;
      _selectedNoteIds.clear();
    });
  }

  void _toggleNoteSelection(String noteId) {
    setState(() {
      if (_selectedNoteIds.contains(noteId)) {
        _selectedNoteIds.remove(noteId);
        if (_selectedNoteIds.isEmpty) {
          _isSelecting = false;
        }
      } else {
        _selectedNoteIds.add(noteId);
      }
    });
  }

  Future<void> _moveNote(domain.Note note) async {
    final result = await MoveToFolderSheet.show(
      context,
      currentFolderId: note.folderId,
      noteCount: 1,
    );
    if (result == null || !mounted) return;

    try {
      final repository = ref.read(notesRepositoryProvider);
      final moved = await repository.moveNotes([note.id], result.targetFolderId);
      if (!mounted) return;
      if (moved > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Moved to ${result.targetFolderName}'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to move note'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _moveSelectedNotes() async {
    if (_selectedNoteIds.isEmpty) return;

    // Determine current folder for disabling in picker.
    // If all selected notes share the same folder, disable it.
    final notes = ref.read(notesStreamProvider).valueOrNull ?? [];
    final selectedNotes =
        notes.where((n) => _selectedNoteIds.contains(n.id)).toList();
    final folderIds = selectedNotes.map((n) => n.folderId).toSet();
    final commonFolderId = folderIds.length == 1 ? folderIds.first : null;

    final result = await MoveToFolderSheet.show(
      context,
      currentFolderId: commonFolderId,
      noteCount: _selectedNoteIds.length,
    );
    if (result == null || !mounted) return;

    try {
      final repository = ref.read(notesRepositoryProvider);
      final moved = await repository.moveNotes(
        _selectedNoteIds.toList(),
        result.targetFolderId,
      );
      if (!mounted) return;
      _exitSelectMode();
      if (moved > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Moved $moved note${moved == 1 ? '' : 's'} to ${result.targetFolderName}'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      _exitSelectMode();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to move notes'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _deleteSelectedNotes() async {
    if (_selectedNoteIds.isEmpty) return;

    final count = _selectedNoteIds.length;
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Move to Trash'),
            content: Text('Move $count selected note${count == 1 ? '' : 's'} to trash?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('Move to Trash'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed || !mounted) return;

    final repository = ref.read(notesRepositoryProvider);
    try {
      for (final id in _selectedNoteIds) {
        await repository.trashNote(id);
      }
      if (!mounted) return;
      final deletedCount = _selectedNoteIds.length;
      _exitSelectMode();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Moved $deletedCount note${deletedCount == 1 ? '' : 's'} to trash'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      _exitSelectMode();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to move notes to trash'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _showFolderSelectionAndCreateNote(BuildContext context) async {
    final result = await FolderSelectionDialog.show(context);

    if (result != null && context.mounted) {
      // Show the template picker so the user starts from a seeded note
      // (sermon notes, prayer journal, etc.) rather than a blank page.
      // The "Blank Note" template is the first option for the previous
      // straight-to-editor behavior.
      await showNoteTemplatePicker(context, folderId: result.folderId);
    }
  }

  List<domain.Note> _sortNotes(List<domain.Note> notes) {
    final sorted = List<domain.Note>.from(notes);
    switch (_sortOption) {
      case NotesSortOption.lastEdited:
        sorted.sort((a, b) => _sortAscending
            ? a.updatedAt.compareTo(b.updatedAt)
            : b.updatedAt.compareTo(a.updatedAt));
        break;
      case NotesSortOption.title:
        sorted.sort((a, b) => _sortAscending
            ? a.title.compareTo(b.title)
            : b.title.compareTo(a.title));
        break;
      case NotesSortOption.createdDate:
        sorted.sort((a, b) => _sortAscending
            ? a.createdAt.compareTo(b.createdAt)
            : b.createdAt.compareTo(a.createdAt));
        break;
    }
    return sorted;
  }

  /// Returns a preview string from the first non-empty block in the main section.
  /// Prayer and personal application blocks are excluded.
  /// Bible reference blocks are rendered as their display reference (e.g. "John 3:16 (KJV)")
  /// rather than raw JSON. Cached by note ID + updatedAt.
  String? _getNotePreview(domain.Note note) {
    final cacheKey = '${note.id}_${note.updatedAt}';
    if (_previewCache.containsKey(cacheKey)) {
      return _previewCache[cacheKey];
    }
    String? preview;
    for (final block in note.document.getBlocksForSection(NoteSection.main)) {
      if (block.type == BlockType.bibleReference) {
        try {
          final json = jsonDecode(block.content) as Map<String, dynamic>;
          final ref = BibleReference.fromJson(json);
          preview = ref.displayReference;
          break;
        } catch (_) {
          continue;
        }
      }
      // Tables also store JSON in `content` — preview their cell text.
      if (block.type == BlockType.table) {
        try {
          final json = jsonDecode(block.content) as Map<String, dynamic>;
          final text = NoteTable.fromJson(json).plainText;
          if (text.isEmpty) continue;
          preview = text;
          break;
        } catch (_) {
          continue;
        }
      }
      if (block.content.trim().isNotEmpty) {
        preview = block.content;
        break;
      }
    }
    if (_previewCache.length >= _previewCacheMaxSize) _previewCache.clear();
    _previewCache[cacheKey] = preview;
    return preview;
  }

  String _formatTimestamp(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inMinutes < 60) {
      return '${diff.inMinutes}m ago';
    } else if (diff.inHours < 24) {
      return '${diff.inHours}h ago';
    } else if (diff.inDays == 1) {
      return 'Yesterday';
    } else if (diff.inDays < 7) {
      return '${diff.inDays} days ago';
    } else {
      final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      return '${months[date.month - 1]} ${date.day}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final shell = StatefulNavigationShell.of(context);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && context.mounted) {
          shell.goBranch(0); // Switch to Home tab
        }
      },
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: _isSelecting
            ? _buildSelectionAppBar(context)
            : _buildNormalAppBar(context),
        floatingActionButton: _isSelecting || _showingTrash
            ? null
            : FloatingActionButton(
                heroTag: null,
                onPressed: () => _showFolderSelectionAndCreateNote(context),
                backgroundColor: AppTheme.brandPurple,
                foregroundColor: Colors.white,
                child: const Icon(Icons.add_rounded),
              ),
        body: _showingTrash
            ? _buildTrashSection(context)
            : Column(
          children: [
            // Folder Section (collapsible accordion)
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              height: _isFolderSectionExpanded
                  ? MediaQuery.of(context).size.height * 0.35
                  : 48,
              child: _buildFolderSection(context),
            ),

            // Notes Section (takes remaining space)
            Expanded(
              child: _buildNotesSection(context),
            ),
          ],
        ),
      ),
    );
  }

  /// Builds the normal app bar
  AppBar _buildNormalAppBar(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return AppBar(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      elevation: 0,
      automaticallyImplyLeading: false,
      title: Text(
        _showingTrash ? 'Trash' : 'Notes',
        style: Theme.of(context).textTheme.titleLarge?.copyWith(
          color: colorScheme.onSurface,
        ),
      ),
      actions: [
        IconButton(
          icon: Icon(
            _showingTrash ? Icons.arrow_back : Icons.delete_outline,
            color: _showingTrash ? colorScheme.onSurface : Colors.grey.shade600,
          ),
          tooltip: _showingTrash ? 'Back to Notes' : 'Trash',
          onPressed: () {
            setState(() {
              _showingTrash = !_showingTrash;
            });
          },
        ),
        if (!_showingTrash) IconButton(
          icon: Icon(Icons.search_rounded, color: Colors.grey.shade600),
          onPressed: () => context.push(Routes.search),
        ),
        if (!_showingTrash) PopupMenuButton<String>(
          icon: Icon(Icons.more_vert_rounded, color: Colors.grey.shade600),
          onSelected: (value) {
            switch (value) {
              case 'select':
                _enterSelectMode();
              default:
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Selected: $value'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'sort',
              child: Text('Sort notes'),
            ),
            const PopupMenuItem(
              value: 'density',
              child: Text('Change view density'),
            ),
            const PopupMenuItem(
              value: 'select',
              child: Text('Select mode'),
            ),
          ],
        ),
      ],
    );
  }

  /// Builds the selection mode app bar with action buttons
  AppBar _buildSelectionAppBar(BuildContext context) {
    final theme = Theme.of(context);
    final count = _selectedNoteIds.length;

    return AppBar(
      backgroundColor: theme.colorScheme.surface,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.close),
        onPressed: _exitSelectMode,
      ),
      title: Text(
        count == 0 ? 'Select notes' : '$count selected',
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.drive_file_move_outlined),
          tooltip: 'Move',
          onPressed: count > 0 ? _moveSelectedNotes : null,
        ),
        IconButton(
          icon: Icon(Icons.delete_outline, color: count > 0 ? Colors.red : null),
          tooltip: 'Move to Trash',
          onPressed: count > 0 ? _deleteSelectedNotes : null,
        ),
      ],
    );
  }

  /// Builds the folder section
  Widget _buildFolderSection(BuildContext context) {
    final foldersAsync = ref.watch(foldersStreamProvider);
    final notesAsync = ref.watch(notesStreamProvider);

    return Container(
      color: Colors.grey.shade50,
      child: Column(
        children: [
          // Collapsible Header
          _buildCollapsibleFolderHeader(context, foldersAsync),

          // Folder List (only visible when expanded)
          if (_isFolderSectionExpanded)
            Expanded(
              child: foldersAsync.when(
                loading: () => const ListTileSkeletonList(count: 4, hasLeading: false),
                error: (e, _) => Center(child: Text('Error: $e')),
                data: (folders) {
                  if (folders.isEmpty) {
                    return Center(
                      child: Text(
                        'No folders yet',
                        style: TextStyle(color: Colors.grey.shade500),
                      ),
                    );
                  }

                  // Get notes to calculate counts per folder
                  final notes = notesAsync.valueOrNull ?? [];

                  // Pre-compute note counts per folder to avoid O(notes*folders)
                  final noteCountByFolder = <String?, int>{};
                  for (final note in notes) {
                    noteCountByFolder[note.folderId] =
                        (noteCountByFolder[note.folderId] ?? 0) + 1;
                  }

                  // Pre-build children map so recursive traversal is O(F) not O(F²)
                  final childrenByParentId = <String?, List<dynamic>>{};
                  for (final folder in folders) {
                    childrenByParentId.putIfAbsent(folder.parentId, () => []).add(folder);
                  }
                  for (final children in childrenByParentId.values) {
                    children.sort((a, b) => a.name.compareTo(b.name));
                  }

                  final roots = childrenByParentId[null] ?? const [];

                  final totalNoteCountById = <String?, int>{};
                  void computeTotal(dynamic folder) {
                    int count = noteCountByFolder[folder.id] ?? 0;
                    for (final child in childrenByParentId[folder.id] ?? const []) {
                      computeTotal(child);
                      count += totalNoteCountById[child.id] ?? 0;
                    }
                    totalNoteCountById[folder.id] = count;
                  }
                  for (final root in roots) {
                    computeTotal(root);
                  }

                  // Build the folder tree widgets
                  final folderWidgets = <Widget>[
                    // "All Notes" option
                    FolderRow(
                      title: 'All Notes',
                      noteCount: notes.length,
                      depth: 0,
                      hasChildren: false,
                      isExpanded: false,
                      isActive: _selectedFolderId == null,
                      onTap: () {
                        setState(() {
                          _selectedFolderId = null;
                          _activeSmartCollection = null;
                        });
                      },
                      onExpandToggle: null,
                    ),
                  ];

                  for (final folder in roots) {
                    folderWidgets.addAll(
                      _buildFolderTreeItems(folder, childrenByParentId, totalNoteCountById, depth: 0),
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.only(bottom: 16),
                    itemCount: folderWidgets.length,
                    itemBuilder: (context, index) => folderWidgets[index],
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _buildFolderTreeItems(
    dynamic folder,
    Map<String?, List<dynamic>> childrenByParentId,
    Map<String?, int> totalNoteCountById, {
    required int depth,
  }) {
    final children = childrenByParentId[folder.id] ?? const [];

    final hasChildren = children.isNotEmpty;
    final isExpanded = _expandedFolders.contains(folder.id);
    final isActive = _selectedFolderId == folder.id;
    final noteCount = totalNoteCountById[folder.id] ?? 0;

    final widgets = <Widget>[
      FolderRow(
        title: folder.name,
        noteCount: noteCount,
        depth: depth,
        hasChildren: hasChildren,
        isExpanded: isExpanded,
        isActive: isActive,
        visibility: folder.visibility,
        onTap: () {
          setState(() {
            _selectedFolderId = folder.id;
            _activeSmartCollection = null;
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
      ),
    ];

    if (isExpanded && hasChildren) {
      for (final child in children) {
        widgets.addAll(
          _buildFolderTreeItems(child, childrenByParentId, totalNoteCountById, depth: depth + 1),
        );
      }
    }

    return widgets;
  }

  /// Builds the notes section
  Widget _buildNotesSection(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final notesAsync = ref.watch(notesStreamProvider);
    final peopleAsync = ref.watch(peopleStreamProvider);

    // Build a map of person ID to name for quick lookup
    final peopleMap = peopleAsync.whenOrNull(
      data: (people) => {for (var p in people) p.id: p.name},
    ) ?? {};

    // Build a map of folder ID to name for display
    final foldersAsync = ref.watch(foldersStreamProvider);
    final folderMap = foldersAsync.whenOrNull(
      data: (folders) => {for (var f in folders) f.id: f.name},
    ) ?? {};

    // Smart collection data (only fetch when active)
    final smartNotes = _activeSmartCollection != null
        ? _getSmartCollectionNotes(ref)
        : null;

    return Container(
      color: colorScheme.surface,
      child: notesAsync.when(
        loading: () => const ListTileSkeletonList(count: 8, hasLeading: false),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (notes) {
          // Smart collection overrides folder/filter selection
          final List<domain.Note> baseNotes;
          if (_activeSmartCollection != null && smartNotes != null) {
            final smartIds = smartNotes.map((n) => n.id).toSet();
            baseNotes = notes.where((n) => smartIds.contains(n.id)).toList();
          } else if (_hasActiveFilters && _filteredNotes != null) {
            baseNotes = _selectedFolderId == null
                ? _filteredNotes!
                : _filteredNotes!
                    .where((n) => n.folderId == _selectedFolderId)
                    .toList();
          } else {
            baseNotes = _selectedFolderId == null
                ? notes
                : notes.where((n) => n.folderId == _selectedFolderId).toList();
          }
          final sortedNotes = _sortNotes(baseNotes);

          // Determine header title based on selection
          final String headerTitle;
          if (_activeSmartCollection != null) {
            headerTitle = _activeSmartCollection!.toUpperCase();
          } else if (_selectedFolderId == null) {
            headerTitle = 'ALL NOTES';
          } else {
            headerTitle = 'NOTES IN FOLDER';
          }

          return Column(
            children: [
              // Smart Collections bar
              _buildSmartCollectionsBar(context),

              // Sticky Header with sort and filter controls
              _buildSectionHeader(
                context,
                title: headerTitle,
                count: sortedNotes.length,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildFilterButton(context),
                    const SizedBox(width: 4),
                    _buildSortControl(context),
                  ],
                ),
              ),

              // Filter bar (shown when filters are active)
              if (_isFilterActive) _buildFilterBar(context),

              // Notes List
              Expanded(
                child: sortedNotes.isEmpty
                    ? _buildEmptyNotesState(context)
                    : ListView.builder(
                        padding: const EdgeInsets.only(top: 8, bottom: 80),
                        itemCount: sortedNotes.length,
                        itemBuilder: (context, index) {
                          final note = sortedNotes[index];
                          final preacherName = note.preacherId != null
                              ? peopleMap[note.preacherId]
                              : null;
                          final folderName = _selectedFolderId == null && note.folderId != null
                              ? folderMap[note.folderId]
                              : null;

                          final isSelected = _selectedNoteIds.contains(note.id);

                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: _isSelecting
                                ? _buildSelectableNoteRow(
                                    note: note,
                                    isSelected: isSelected,
                                    preacherName: preacherName,
                                    folderName: folderName,
                                  )
                                : Slidable(
                                    key: Key(note.id),
                                    endActionPane: ActionPane(
                                      motion: const DrawerMotion(),
                                      extentRatio: 0.45,
                                      children: [
                                        CustomSlidableAction(
                                          onPressed: (_) => _moveNote(note),
                                          padding: EdgeInsets.zero,
                                          child: Container(
                                            margin: const EdgeInsets.only(left: 8, right: 4),
                                            decoration: BoxDecoration(
                                              color: AppTheme.brandPurple,
                                              borderRadius: BorderRadius.circular(12),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: AppTheme.brandPurple.withValues(alpha: 0.3),
                                                  blurRadius: 8,
                                                  offset: const Offset(0, 2),
                                                ),
                                              ],
                                            ),
                                            child: const Center(
                                              child: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(Icons.drive_file_move_outlined, color: Colors.white, size: 22),
                                                  SizedBox(height: 4),
                                                  Text('Move', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500)),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                        CustomSlidableAction(
                                          onPressed: (context) async {
                                            final shouldDelete = await _showDeleteConfirmation(context);
                                            if (shouldDelete) {
                                              _deleteNote(note.id);
                                            }
                                          },
                                          padding: EdgeInsets.zero,
                                          child: Container(
                                            margin: const EdgeInsets.only(left: 4, right: 8),
                                            decoration: BoxDecoration(
                                              color: Colors.red,
                                              borderRadius: BorderRadius.circular(12),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: Colors.red.withValues(alpha: 0.3),
                                                  blurRadius: 8,
                                                  offset: const Offset(0, 2),
                                                ),
                                              ],
                                            ),
                                            child: const Center(
                                              child: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(Icons.delete, color: Colors.white, size: 22),
                                                  SizedBox(height: 4),
                                                  Text('Trash', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500)),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    child: NoteRow(
                                      title: note.title,
                                      preview: _getNotePreview(note),
                                      noteDate: note.noteDate,
                                      preacherName: preacherName,
                                      folderName: folderName,
                                      tags: const [],
                                      onTap: () => context.push('/notes/${note.id}'),
                                      onLongPress: () => _enterSelectMode(initialNoteId: note.id),
                                    ),
                                  ),
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

  /// Builds the collapsible folder section header
  Widget _buildCollapsibleFolderHeader(BuildContext context, AsyncValue<List<dynamic>> foldersAsync) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final folderCount = foldersAsync.when(
      data: (folders) => folders.length,
      loading: () => 0,
      error: (e, s) => 0,
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _toggleFolderSection,
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: Colors.grey.shade200,
                width: 1,
              ),
            ),
          ),
          child: Row(
            children: [
              // Expand/collapse indicator
              AnimatedRotation(
                turns: _isFolderSectionExpanded ? 0.25 : 0,
                duration: const Duration(milliseconds: 300),
                child: Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
              const SizedBox(width: 8),
              // Title and count
              Text(
                'FOLDERS ($folderCount)',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: Colors.grey,
                  letterSpacing: 0.5,
                ),
              ),
              const Spacer(),
              // Add folder button
              IconButton(
                icon: Icon(
                  Icons.create_new_folder_rounded,
                  color: AppTheme.brandPurple,
                  size: 20,
                ),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const FolderManagementScreen(),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Builds a section header with title, count, and optional trailing widget
  Widget _buildSectionHeader(
    BuildContext context, {
    required String title,
    required int count,
    Widget? trailing,
  }) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Colors.grey.shade200,
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          Text(
            '$title ($count)',
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: Colors.grey,
              letterSpacing: 0.5,
            ),
          ),
          const Spacer(),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  /// Builds the filter toggle button with active count badge
  Widget _buildFilterButton(BuildContext context) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _isFilterActive = !_isFilterActive;
        });
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _isFilterActive
                ? Icons.filter_list_rounded
                : Icons.filter_list_off_rounded,
            size: 18,
            color: _hasActiveFilters
                ? AppTheme.brandPurple
                : Colors.grey,
          ),
          if (_hasActiveFilters) ...[
            const SizedBox(width: 2),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: AppTheme.brandPurple,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '$_activeFilterCount',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Builds the filter bar with tag, preacher, and date range chips
  Widget _buildFilterBar(BuildContext context) {
    final tagsAsync = ref.watch(tagsStreamProvider);
    final peopleAsync = ref.watch(peopleStreamProvider);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade200, width: 1),
        ),
      ),
      child: Row(
        children: [
          // Tag filter chip
          Expanded(
            child: tagsAsync.when(
              loading: () => const SizedBox.shrink(),
              error: (_, _) => const SizedBox.shrink(),
              data: (tags) => _FilterChip(
                icon: Icons.label_outlined,
                label: _filterTagIds.isEmpty
                    ? 'Tags'
                    : '${_filterTagIds.length} tag${_filterTagIds.length == 1 ? '' : 's'}',
                isActive: _filterTagIds.isNotEmpty,
                onTap: () => _showTagFilterSheet(context, tags),
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Preacher filter chip
          Expanded(
            child: peopleAsync.when(
              loading: () => const SizedBox.shrink(),
              error: (_, _) => const SizedBox.shrink(),
              data: (people) {
                final selectedName = _filterPreacherId != null
                    ? people
                        .where((p) => p.id == _filterPreacherId)
                        .map((p) => p.name)
                        .firstOrNull
                    : null;
                return _FilterChip(
                  icon: Icons.person_outlined,
                  label: selectedName ?? 'Preacher',
                  isActive: _filterPreacherId != null,
                  onTap: () => _showPreacherFilterSheet(context, people),
                );
              },
            ),
          ),
          const SizedBox(width: 8),

          // Date range chip
          Expanded(
            child: _FilterChip(
              icon: Icons.calendar_today_outlined,
              label: _filterDateRange != null
                  ? '${_filterDateRange!.start.day}/${_filterDateRange!.start.month} – ${_filterDateRange!.end.day}/${_filterDateRange!.end.month}'
                  : 'Date',
              isActive: _filterDateRange != null,
              onTap: () => _showDateRangeFilter(context),
            ),
          ),

          // Clear all
          if (_hasActiveFilters) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _clearFilters,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                ),
                child: const Icon(Icons.close, size: 16, color: Colors.red),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Shared bottom sheet header for all filter sheets
  Widget _buildFilterSheetHeader(BuildContext context, String title) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 8, 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade200),
        ),
      ),
      child: Row(
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  void _showTagFilterSheet(BuildContext context, List<dynamic> tags) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildFilterSheetHeader(context, 'Filter by Tags'),
                  if (tags.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 32),
                      child: Column(
                        children: [
                          Icon(Icons.label_off_outlined,
                              size: 40, color: Colors.grey.shade400),
                          const SizedBox(height: 8),
                          Text('No tags available',
                              style: TextStyle(color: Colors.grey.shade600)),
                        ],
                      ),
                    )
                  else
                    ...tags.map((tag) {
                      final isSelected = _filterTagIds.contains(tag.id);
                      return CheckboxListTile(
                        title: Text(tag.name),
                        value: isSelected,
                        activeColor: AppTheme.brandPurple,
                        controlAffinity: ListTileControlAffinity.leading,
                        dense: true,
                        onChanged: (value) {
                          setSheetState(() {
                            setState(() {
                              if (value == true) {
                                _filterTagIds.add(tag.id);
                              } else {
                                _filterTagIds.remove(tag.id);
                              }
                            });
                          });
                        },
                      );
                    }),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.brandPurple),
                      onPressed: () {
                        Navigator.pop(context);
                        _applyFilters();
                      },
                      child: const Text('Apply'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showPreacherFilterSheet(
      BuildContext context, List<dynamic> people) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildFilterSheetHeader(context, 'Filter by Preacher'),
                  if (people.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 32),
                      child: Column(
                        children: [
                          Icon(Icons.person_off_outlined,
                              size: 40, color: Colors.grey.shade400),
                          const SizedBox(height: 8),
                          Text('No people available',
                              style: TextStyle(color: Colors.grey.shade600)),
                          const SizedBox(height: 4),
                          Text('Add people via note details',
                              style: TextStyle(
                                  color: Colors.grey.shade400, fontSize: 12)),
                        ],
                      ),
                    )
                  else ...[
                    // "Any preacher" option to clear
                    ListTile(
                      title: const Text('Any preacher'),
                      leading: Icon(
                        _filterPreacherId == null
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                        color: _filterPreacherId == null
                            ? AppTheme.brandPurple
                            : Colors.grey,
                        size: 20,
                      ),
                      dense: true,
                      onTap: () {
                        setSheetState(() {
                          setState(() => _filterPreacherId = null);
                        });
                      },
                    ),
                    ...people.map((person) {
                      final isSelected = _filterPreacherId == person.id;
                      return ListTile(
                        title: Text(person.name),
                        leading: Icon(
                          isSelected
                              ? Icons.radio_button_checked
                              : Icons.radio_button_unchecked,
                          color: isSelected
                              ? AppTheme.brandPurple
                              : Colors.grey,
                          size: 20,
                        ),
                        dense: true,
                        onTap: () {
                          setSheetState(() {
                            setState(() => _filterPreacherId = person.id);
                          });
                        },
                      );
                    }),
                  ],
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.brandPurple),
                      onPressed: () {
                        Navigator.pop(context);
                        _applyFilters();
                      },
                      child: const Text('Apply'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showDateRangeFilter(BuildContext context) async {
    await showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final now = DateTime.now();
            final presets = [
              (label: 'Last 7 days', range: DateTimeRange(start: now.subtract(const Duration(days: 7)), end: now)),
              (label: 'Last 30 days', range: DateTimeRange(start: now.subtract(const Duration(days: 30)), end: now)),
              (label: 'Last 90 days', range: DateTimeRange(start: now.subtract(const Duration(days: 90)), end: now)),
              (label: 'This year', range: DateTimeRange(start: DateTime(now.year), end: now)),
            ];

            return SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildFilterSheetHeader(context, 'Filter by Date'),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                  // Preset options
                  ListTile(
                    title: const Text('Any date'),
                    leading: Icon(
                      _filterDateRange == null
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      color: _filterDateRange == null
                          ? AppTheme.brandPurple
                          : Colors.grey,
                      size: 20,
                    ),
                    dense: true,
                    onTap: () {
                      setSheetState(() {
                        setState(() => _filterDateRange = null);
                      });
                    },
                  ),
                  ...presets.map((preset) {
                    final isSelected = _filterDateRange != null &&
                        _filterDateRange!.start.day == preset.range.start.day &&
                        _filterDateRange!.start.month == preset.range.start.month &&
                        _filterDateRange!.end.day == preset.range.end.day;
                    return ListTile(
                      title: Text(preset.label),
                      leading: Icon(
                        isSelected
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                        color: isSelected
                            ? AppTheme.brandPurple
                            : Colors.grey,
                        size: 20,
                      ),
                      dense: true,
                      onTap: () {
                        setSheetState(() {
                          setState(() => _filterDateRange = preset.range);
                        });
                      },
                    );
                  }),
                  // Custom range option
                  ListTile(
                    leading: const Icon(Icons.date_range_outlined, size: 20),
                    title: const Text('Custom range...'),
                    dense: true,
                    onTap: () async {
                      Navigator.pop(context);
                      final picked = await showDateRangePicker(
                        context: this.context,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                        initialDateRange: _filterDateRange,
                        builder: (context, child) {
                          return Theme(
                            data: Theme.of(context).copyWith(
                              colorScheme: Theme.of(context).colorScheme.copyWith(
                                    primary: AppTheme.brandPurple,
                                  ),
                            ),
                            child: child!,
                          );
                        },
                      );
                      if (picked != null) {
                        setState(() => _filterDateRange = picked);
                        _applyFilters();
                      }
                    },
                  ),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.brandPurple),
                      onPressed: () {
                        Navigator.pop(context);
                        _applyFilters();
                      },
                      child: const Text('Apply'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  /// Builds the sort control dropdown
  Widget _buildSortControl(BuildContext context) {
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: () {
        _showSortOptions(context);
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _sortOption.label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: AppTheme.brandPurple,
            ),
          ),
          const SizedBox(width: 4),
          Icon(
            _sortAscending ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
            size: 14,
            color: AppTheme.brandPurple,
          ),
        ],
      ),
    );
  }

  /// Shows sort options bottom sheet
  void _showSortOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildFilterSheetHeader(context, 'Sort by'),
                  ...NotesSortOption.values.map((option) {
                    final isSelected = _sortOption == option;
                    return ListTile(
                      title: Text(option.label),
                      leading: Icon(
                        isSelected
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                        color: isSelected ? AppTheme.brandPurple : Colors.grey,
                        size: 20,
                      ),
                      dense: true,
                      onTap: () {
                        setSheetState(() {
                          setState(() => _sortOption = option);
                        });
                      },
                    );
                  }),
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      children: [
                        Text(
                          'Direction',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade700,
                          ),
                        ),
                        const Spacer(),
                        GestureDetector(
                          onTap: () {
                            setSheetState(() {
                              setState(() => _sortAscending = true);
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: _sortAscending
                                  ? AppTheme.brandPurple.withValues(alpha: 0.1)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: _sortAscending
                                    ? AppTheme.brandPurple
                                    : Colors.grey.shade300,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.arrow_upward_rounded, size: 14,
                                    color: _sortAscending ? AppTheme.brandPurple : Colors.grey.shade600),
                                const SizedBox(width: 4),
                                Text('Asc',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: _sortAscending ? FontWeight.w600 : FontWeight.normal,
                                      color: _sortAscending ? AppTheme.brandPurple : Colors.grey.shade600,
                                    )),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () {
                            setSheetState(() {
                              setState(() => _sortAscending = false);
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: !_sortAscending
                                  ? AppTheme.brandPurple.withValues(alpha: 0.1)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: !_sortAscending
                                    ? AppTheme.brandPurple
                                    : Colors.grey.shade300,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.arrow_downward_rounded, size: 14,
                                    color: !_sortAscending ? AppTheme.brandPurple : Colors.grey.shade600),
                                const SizedBox(width: 4),
                                Text('Desc',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: !_sortAscending ? FontWeight.w600 : FontWeight.normal,
                                      color: !_sortAscending ? AppTheme.brandPurple : Colors.grey.shade600,
                                    )),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<bool> _showDeleteConfirmation(BuildContext context) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Move to Trash'),
            content: const Text('Are you sure you want to move this note to trash?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('Move to Trash'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _deleteNote(String noteId) async {
    final repository = ref.read(notesRepositoryProvider);
    try {
      await repository.trashNote(noteId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Moved to trash'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to move note to trash'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// Builds a note row with a leading checkbox for multi-select mode
  Widget _buildSelectableNoteRow({
    required domain.Note note,
    required bool isSelected,
    String? preacherName,
    String? folderName,
  }) {
    return Row(
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 16),
          child: Checkbox(
            value: isSelected,
            activeColor: AppTheme.brandPurple,
            onChanged: (_) => _toggleNoteSelection(note.id),
          ),
        ),
        Expanded(
          child: NoteRow(
            title: note.title,
            preview: _getNotePreview(note),
            noteDate: note.noteDate,
            preacherName: preacherName,
            folderName: folderName,
            tags: const [],
            onTap: () => _toggleNoteSelection(note.id),
          ),
        ),
      ],
    );
  }

  /// Returns NoteModel list for the active smart collection, or null.
  List<NoteModel>? _getSmartCollectionNotes(WidgetRef ref) {
    switch (_activeSmartCollection) {
      case 'Recently Edited':
        return ref.watch(recentlyEditedNotesProvider).valueOrNull;
      case 'Untagged':
        return ref.watch(untaggedNotesProvider).valueOrNull;
      case 'No Activity 30d':
        return ref.watch(staleNotesProvider).valueOrNull;
      default:
        return null;
    }
  }

  /// Smart collections horizontal chip bar.
  Widget _buildSmartCollectionsBar(BuildContext context) {
    final collections = [
      (name: 'Recently Edited', icon: Icons.history_rounded, provider: recentlyEditedNotesProvider),
      (name: 'Untagged', icon: Icons.label_off_rounded, provider: untaggedNotesProvider),
      (name: 'No Activity 30d', icon: Icons.hourglass_empty_rounded, provider: staleNotesProvider),
    ];

    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade200, width: 1),
        ),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: collections.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final c = collections[index];
          final isActive = _activeSmartCollection == c.name;
          final countAsync = ref.watch(c.provider);
          final count = countAsync.valueOrNull?.length;

          return GestureDetector(
            onTap: () {
              setState(() {
                if (isActive) {
                  _activeSmartCollection = null;
                } else {
                  _activeSmartCollection = c.name;
                  _selectedFolderId = null;
                }
              });
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: isActive
                    ? AppTheme.brandPurple
                    : Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isActive
                      ? AppTheme.brandPurple
                      : Colors.grey.shade300,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    c.icon,
                    size: 14,
                    color: isActive ? Colors.white : Colors.grey.shade600,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    c.name,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: isActive ? Colors.white : Colors.grey.shade700,
                    ),
                  ),
                  if (count != null) ...[
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: isActive
                            ? Colors.white.withValues(alpha: 0.25)
                            : Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '$count',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: isActive ? Colors.white : Colors.grey.shade600,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// Builds the trash section showing trashed notes with restore/delete actions
  Widget _buildTrashSection(BuildContext context) {
    final trashedNotesAsync = ref.watch(trashedNotesStreamProvider);
    final colorScheme = Theme.of(context).colorScheme;

    return trashedNotesAsync.when(
      loading: () => const ListTileSkeletonList(count: 8, hasLeading: false),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (trashedNotes) {
        if (trashedNotes.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.delete_outline,
                    size: 64,
                    color: colorScheme.onSurface.withValues(alpha: 0.3),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Trash is empty',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.only(top: 8, bottom: 80),
          itemCount: trashedNotes.length,
          itemBuilder: (context, index) {
            final note = trashedNotes[index];
            final title = note.title.isEmpty ? 'Untitled Note' : note.title;

            return Slidable(
              key: Key(note.id),
              startActionPane: ActionPane(
                motion: const DrawerMotion(),
                extentRatio: 0.25,
                children: [
                  CustomSlidableAction(
                    onPressed: (_) => _restoreNote(note.id, title),
                    padding: EdgeInsets.zero,
                    child: Container(
                      margin: const EdgeInsets.only(left: 8, right: 4),
                      decoration: BoxDecoration(
                        color: Colors.green,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.green.withValues(alpha: 0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.restore, color: Colors.white, size: 22),
                            SizedBox(height: 4),
                            Text('Restore', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              endActionPane: ActionPane(
                motion: const DrawerMotion(),
                extentRatio: 0.25,
                children: [
                  CustomSlidableAction(
                    onPressed: (_) => _permanentlyDeleteNote(note.id, title),
                    padding: EdgeInsets.zero,
                    child: Container(
                      margin: const EdgeInsets.only(left: 4, right: 8),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.red.withValues(alpha: 0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.delete_forever, color: Colors.white, size: 22),
                            SizedBox(height: 4),
                            Text('Delete', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              child: ListTile(
                leading: Icon(Icons.note_outlined, color: Colors.grey.shade500),
                title: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  'Trashed ${_formatTimestamp(DateTime.fromMillisecondsSinceEpoch(note.updatedAt))}',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.restore, color: Colors.green, size: 20),
                      tooltip: 'Restore',
                      onPressed: () => _restoreNote(note.id, title),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_forever, color: Colors.red, size: 20),
                      tooltip: 'Delete permanently',
                      onPressed: () => _permanentlyDeleteNote(note.id, title),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _restoreNote(String noteId, String title) async {
    try {
      await ref.read(noteRepositoryProvider).restoreNote(noteId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Restored "$title"'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to restore note'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _permanentlyDeleteNote(String noteId, String title) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Delete Permanently'),
            content: Text('Permanently delete "$title"? This cannot be undone.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed || !mounted) return;

    try {
      await ref.read(noteRepositoryProvider).deleteNote(noteId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Permanently deleted "$title"'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to delete note'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// Builds empty state for notes section
  Widget _buildEmptyNotesState(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.note_add_rounded,
              size: 64,
              color: colorScheme.onSurface.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Text(
              'No notes yet',
              style: theme.textTheme.titleMedium?.copyWith(
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Tap + to create your first note',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Reusable filter chip for the filter bar
class _FilterChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _FilterChip({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isActive
              ? AppTheme.brandPurple.withValues(alpha: 0.08)
              : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isActive ? AppTheme.brandPurple : Colors.grey.shade300,
            width: isActive ? 1.5 : 0.5,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isActive ? Icons.check_rounded : icon,
              size: 14,
              color: isActive ? AppTheme.brandPurple : Colors.grey.shade500,
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: isActive ? AppTheme.brandPurple : Colors.grey.shade700,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
