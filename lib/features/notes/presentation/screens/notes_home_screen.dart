import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:go_router/go_router.dart';

import '../../domain/models/block_type.dart';
import '../../domain/models/note_section.dart';
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
import '../../../../shared/widgets/undo_snackbar.dart';
import '../../../../core/services/user_facing_error.dart';
import '../../../../shared/widgets/row_actions.dart';
import '../../../../shared/widgets/feature_intro.dart';
import '../../../../core/providers/motion_preferences.dart';
import '../../../../shared/widgets/swipe_action.dart';
import '../../../../core/theme/theme_colors.dart';
import '../../../../l10n/l10n.dart';
import '../../../../core/navigation/tab_navigation.dart';
import '../../../../shared/widgets/filter_pill.dart';

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
        SnackBar(
          content: Text(l10n(context).failedToMoveNote),
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
        SnackBar(
          content: Text(l10n(context).failedToMoveNotes),
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
            title: Text(l10n(context).moveToTrash),
            content: Text('Move $count selected note${count == 1 ? '' : 's'} to trash?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(l10n(context).actionCancel),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: Text(l10n(context).moveToTrash),
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
        SnackBar(
          content: Text(l10n(context).failedToMoveNotesToTrash),
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

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && context.mounted) {
          goToTab(context, 0); // Switch to Home tab
        }
      },
      child: Scaffold(
        // Same ground as every other tab. What made the top of this list look
        // muddy was not the page grey but the two *extra* greys stacked on it
        // — the folder band and the filter bar each had their own fill. Those
        // now match the page, so there is one grey rather than three.
        backgroundColor: context.pageGround,
        appBar: _isSelecting
            ? _buildSelectionAppBar(context)
            : _buildNormalAppBar(context),
        floatingActionButton: _isSelecting || _showingTrash
            ? null
            : FloatingActionButton(
                heroTag: null,
                onPressed: () => _showFolderSelectionAndCreateNote(context),
                backgroundColor: AppTheme.brandPurple,
                foregroundColor: AppTheme.onAccent(AppTheme.brandPurple),
                child: const Icon(Icons.add_rounded),
              ),
        body: _showingTrash
            ? _buildTrashSection(context)
            : Column(
          children: [
            // Folder Section (collapsible accordion)
            AnimatedContainer(
              duration: context.motion(const Duration(milliseconds: 300)),
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
          tooltip: l10n(context).actionSearch,
          icon: Icon(Icons.search_rounded, color: Theme.of(context).colorScheme.onSurfaceVariant),
          onPressed: () => context.push(Routes.search),
        ),
        if (!_showingTrash) PopupMenuButton<String>(
          icon: Icon(Icons.more_vert_rounded, color: Theme.of(context).colorScheme.onSurfaceVariant),
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
            PopupMenuItem(
              value: 'sort',
              child: Text(l10n(context).sortNotes),
            ),
            PopupMenuItem(
              value: 'density',
              child: Text(l10n(context).changeViewDensity),
            ),
            PopupMenuItem(
              value: 'select',
              child: Text(l10n(context).selectMode),
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
        tooltip: l10n(context).exitSelection,
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
          tooltip: l10n(context).move,
          onPressed: count > 0 ? _moveSelectedNotes : null,
        ),
        IconButton(
          icon: Icon(Icons.delete_outline, color: count > 0 ? Colors.red : null),
          tooltip: l10n(context).moveToTrash,
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
      // The folder section is part of the page, not a raised panel. A filled
      // band here reads as a grey slab across the top of the list — it was
      // Colors.grey.shade100 before, which the theme migration turned into a
      // heavier container fill.
      color: context.pageGround,
      child: Column(
        children: [
          // Collapsible Header
          _buildCollapsibleFolderHeader(context, foldersAsync),

          // Folder List (only visible when expanded)
          if (_isFolderSectionExpanded)
            Expanded(
              child: foldersAsync.when(
                loading: () => const ListTileSkeletonList(count: 4, hasLeading: false),
                error: (e, _) => Center(child: Text(UserFacingError.forLoad(e))),
                data: (folders) {
                  if (folders.isEmpty) {
                    return Center(
                      child: Text(
                        l10n(context).noFoldersYet,
                        style: TextStyle(color: context.mutedText),
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
                      title: l10n(context).allNotes,
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
      // The list sits directly on the page, as it does on every other tab. A
      // white block here put the rows on a different ground from the folder
      // band above them.
      color: context.pageGround,
      child: notesAsync.when(
        loading: () => const ListTileSkeletonList(count: 8, hasLeading: false),
        error: (e, _) => Center(child: Text(UserFacingError.forLoad(e))),
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
                        itemCount: sortedNotes.length + 1,
                        itemBuilder: (context, index) {
                          if (index == 0) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 16),
                              child: FeatureIntros.notes,
                            );
                          }
                          final note = sortedNotes[index - 1];
                          final preacherName = note.preacherId != null
                              ? peopleMap[note.preacherId]
                              : null;
                          final folderName = _selectedFolderId == null && note.folderId != null
                              ? folderMap[note.folderId]
                              : null;

                          final isSelected = _selectedNoteIds.contains(note.id);

                          // Spacing comes from NoteRow's own cardMargin (4
                          // top and bottom). A wrapper here used to add 6
                          // more on each side, putting consecutive rows 20px
                          // apart where every other list leaves 8.
                          return _isSelecting
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
                                    extentRatio: swipePaneExtent(2),
                                    children: [
                                      buildSwipeAction(
                                        icon: Icons.drive_file_move_outlined,
                                        label: l10n(context).move,
                                        accent: AppTheme.brandPurple,
                                        isLast: false,
                                        onPressed: (_) => _moveNote(note),
                                      ),
                                      buildSwipeAction(
                                        icon: Icons.delete_outline_rounded,
                                        label: l10n(context).trash,
                                        accent: AppTheme.error,
                                        isFirst: false,
                                        onPressed: (context) async {
                                          final shouldDelete =
                                              await _showDeleteConfirmation(
                                                  context);
                                          if (shouldDelete) {
                                            _deleteNote(note.id);
                                          }
                                        },
                                      ),
                                    ],
                                  ),
                                  child: NoteRow(
                                    title: note.displayTitle,
                                    preview: _getNotePreview(note),
                                    noteDate: note.noteDate,
                                    preacherName: preacherName,
                                    folderName: folderName,
                                    tags: const [],
                                    onTap: () => context.push('/notes/${note.id}'),
                                    onLongPress: () => _enterSelectMode(initialNoteId: note.id),
                                    actions: [
                                      RowAction(
                                        icon: Icons.checklist_rounded,
                                        label: l10n(context).select,
                                        onSelected: () => _enterSelectMode(
                                            initialNoteId: note.id),
                                      ),
                                      RowAction(
                                        icon: Icons.delete_outline_rounded,
                                        label: l10n(context).moveToTrash,
                                        isDestructive: true,
                                        onSelected: () => _deleteNote(note.id),
                                      ),
                                    ],
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
                color: context.hairline,
                width: 1,
              ),
            ),
          ),
          child: Row(
            children: [
              // Expand/collapse indicator
              AnimatedRotation(
                turns: _isFolderSectionExpanded ? 0.25 : 0,
                duration: context.motion(const Duration(milliseconds: 300)),
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
                  color: context.mutedText,
                  letterSpacing: 0.5,
                ),
              ),
              const Spacer(),
              // Add folder button
              IconButton(
                tooltip: l10n(context).newFolder,
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
            color: context.hairline,
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
              color: context.mutedText,
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
                : context.mutedText,
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
                    fontSize: 12,
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
        color: context.pageGround,
        border: Border(
          bottom: BorderSide(color: context.hairline, width: 1),
        ),
      ),
      child: Row(
        children: [
          // Tag filter chip
          Expanded(
            child: tagsAsync.when(
              loading: () => const SizedBox.shrink(),
              error: (_, _) => const SizedBox.shrink(),
              data: (tags) => FilterPill(
                icon: Icons.label_outlined,
                label: _filterTagIds.isEmpty
                    ? 'Tags'
                    : '${_filterTagIds.length} tag${_filterTagIds.length == 1 ? '' : 's'}',
                selected: _filterTagIds.isNotEmpty,
                onTap: () => _showTagFilterSheet(context, tags),
                accent: AppTheme.brandPurple,),
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
                return FilterPill(
                  icon: Icons.person_outlined,
                  label: selectedName ?? 'Preacher',
                  selected: _filterPreacherId != null,
                  onTap: () => _showPreacherFilterSheet(context, people),
                  accent: AppTheme.brandPurple,);
              },
            ),
          ),
          const SizedBox(width: 8),

          // Date range chip
          Expanded(
            child: FilterPill(
              icon: Icons.calendar_today_outlined,
              label: _filterDateRange != null
                  ? '${_filterDateRange!.start.day}/${_filterDateRange!.start.month} – ${_filterDateRange!.end.day}/${_filterDateRange!.end.month}'
                  : 'Date',
              selected: _filterDateRange != null,
              onTap: () => _showDateRangeFilter(context),
              accent: AppTheme.brandPurple,),
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
                child: Icon(Icons.close, size: 16, color: context.dangerText),
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
          bottom: BorderSide(color: context.hairline),
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
            tooltip: l10n(context).close,
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
      // Defaults to false: a scroll-controlled sheet otherwise draws its
      // top edge behind the notch or Dynamic Island.
      useSafeArea: true,
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
                              size: 40, color: context.hintText),
                          const SizedBox(height: 8),
                          Text(l10n(context).noTagsAvailable,
                              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
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
                      child: Text(l10n(context).apply),
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
      // Defaults to false: a scroll-controlled sheet otherwise draws its
      // top edge behind the notch or Dynamic Island.
      useSafeArea: true,
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
                              size: 40, color: context.hintText),
                          const SizedBox(height: 8),
                          Text(l10n(context).noPeopleAvailable,
                              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                          const SizedBox(height: 4),
                          Text(l10n(context).addPeopleViaNoteDetails,
                              style: TextStyle(
                                  color: context.hintText, fontSize: 13)),
                        ],
                      ),
                    )
                  else ...[
                    // "Any preacher" option to clear
                    ListTile(
                      title: Text(l10n(context).anyPreacher),
                      leading: Icon(
                        _filterPreacherId == null
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                        color: _filterPreacherId == null
                            ? AppTheme.brandPurple
                            : context.mutedText,
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
                              : context.mutedText,
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
                      child: Text(l10n(context).apply),
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
      // Defaults to false: a scroll-controlled sheet otherwise draws its
      // top edge behind the notch or Dynamic Island.
      useSafeArea: true,
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final now = DateTime.now();
            final presets = [
              (label: l10n(context).last7Days, range: DateTimeRange(start: now.subtract(const Duration(days: 7)), end: now)),
              (label: l10n(context).last30Days, range: DateTimeRange(start: now.subtract(const Duration(days: 30)), end: now)),
              (label: l10n(context).last90Days, range: DateTimeRange(start: now.subtract(const Duration(days: 90)), end: now)),
              (label: l10n(context).thisYear, range: DateTimeRange(start: DateTime(now.year), end: now)),
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
                    title: Text(l10n(context).anyDate),
                    leading: Icon(
                      _filterDateRange == null
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      color: _filterDateRange == null
                          ? AppTheme.brandPurple
                          : context.mutedText,
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
                            : context.mutedText,
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
                    title: Text(l10n(context).customRange),
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
                      child: Text(l10n(context).apply),
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
      // Defaults to false: a scroll-controlled sheet otherwise draws its
      // top edge behind the notch or Dynamic Island.
      useSafeArea: true,
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
                          l10n(context).direction,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                                    : context.hairline,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.arrow_upward_rounded, size: 14,
                                    color: _sortAscending ? AppTheme.brandPurple : Colors.grey.shade600),
                                const SizedBox(width: 4),
                                Text(l10n(context).asc,
                                    style: TextStyle(
                                      fontSize: 13,
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
                                    : context.hairline,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.arrow_downward_rounded, size: 14,
                                    color: !_sortAscending ? AppTheme.brandPurple : Colors.grey.shade600),
                                const SizedBox(width: 4),
                                Text(l10n(context).desc,
                                    style: TextStyle(
                                      fontSize: 13,
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
            title: Text(l10n(context).moveToTrash),
            content: Text(l10n(context).areYouSureYouWantToMoveThisNoteToTrash),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(l10n(context).actionCancel),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: Text(l10n(context).moveToTrash),
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
      showUndoSnackBar(
        context,
        itemLabel: 'Note',
        onUndo: () => repository.restoreNote(noteId),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n(context).failedToMoveNoteToTrash),
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
            title: note.displayTitle,
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
        color: context.pageGround,
        border: Border(
          bottom: BorderSide(color: context.hairline, width: 1),
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
                      : context.hairline,
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
                      fontSize: 13,
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
                            : context.subtleFill,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '$count',
                        style: TextStyle(
                          fontSize: 12,
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
      error: (e, _) => Center(child: Text(UserFacingError.forLoad(e))),
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
                    l10n(context).trashEmptyTitle,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: context.mutedText,
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
            final title =
                note.title.isEmpty ? domain.Note.untitledLabel : note.title;

            return Slidable(
              key: Key(note.id),
              startActionPane: ActionPane(
                motion: const DrawerMotion(),
                extentRatio: swipePaneExtent(1),
                children: [
                  buildSwipeAction(
                    icon: Icons.restore_rounded,
                    label: l10n(context).restore,
                    accent: AppTheme.emerald,
                    onPressed: (_) => _restoreNote(note.id, title),
                  ),
                ],
              ),
              endActionPane: ActionPane(
                motion: const DrawerMotion(),
                extentRatio: swipePaneExtent(1),
                children: [
                  buildSwipeAction(
                    icon: Icons.delete_forever_rounded,
                    label: l10n(context).actionDelete,
                    accent: AppTheme.error,
                    onPressed: (_) => _permanentlyDeleteNote(note.id, title),
                  ),
                ],
              ),
              child: ListTile(
                leading: Icon(Icons.note_outlined, color: context.mutedText),
                title: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  'Trashed ${_formatTimestamp(DateTime.fromMillisecondsSinceEpoch(note.updatedAt))}',
                  style: TextStyle(fontSize: 13, color: context.mutedText),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(Icons.restore, color: context.successText, size: 20),
                      tooltip: l10n(context).restore,
                      onPressed: () => _restoreNote(note.id, title),
                    ),
                    IconButton(
                      icon: Icon(Icons.delete_forever, color: context.dangerText, size: 20),
                      tooltip: l10n(context).deletePermanently,
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
        SnackBar(
          content: Text(l10n(context).failedToRestoreNote),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _permanentlyDeleteNote(String noteId, String title) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(l10n(context).deletePermanently),
            content: Text('Permanently delete "$title"? This cannot be undone.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(l10n(context).actionCancel),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: Text(l10n(context).actionDelete),
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
        SnackBar(
          content: Text(l10n(context).failedToDeleteNote),
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
              l10n(context).emptyNotesTitle,
              style: theme.textTheme.titleMedium?.copyWith(
                color: context.mutedText,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n(context).tapToCreateYourFirstNote,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: context.mutedText,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

