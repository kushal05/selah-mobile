import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:go_router/go_router.dart';

import '../../domain/models/block_type.dart';
import '../../domain/models/note_section.dart';
import '../../domain/models/notes_sort_option.dart';
import '../../../bible/domain/models/bible_reference.dart';
import '../../../../core/navigation/routes.dart';
import '../../../../core/sync/models/note_model.dart';
import '../../../../core/sync/providers/sync_providers.dart';
import '../../domain/models/note.dart' as domain;
import '../providers/database_provider.dart';
import '../providers/note_display_lookups.dart';
import '../providers/notes_home_ui_state.dart';
import '../../../../shared/widgets/dialogs/folder_selection_dialog.dart';
import '../../../../shared/widgets/cards/note_row.dart';
import '../../../../shared/widgets/dialogs/move_to_folder_sheet.dart';
import '../widgets/folder_section.dart';
import '../widgets/note_template_picker_sheet.dart';
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
import '../../../../shared/utils/date_format.dart';
import '../../../../shared/widgets/tab_title.dart';

/// Notes list screen showing folders and notes in a split layout
class NotesHomeScreen extends ConsumerStatefulWidget {
  /// Opens with this tag already applied to the filter.
  ///
  /// Set when arriving from a verse tag in the Bible reader, so tapping the
  /// tag lands on the notes that carry it rather than on an unfiltered list
  /// the user then has to narrow by hand.
  final String? initialTagId;

  const NotesHomeScreen({super.key, this.initialTagId});

  @override
  ConsumerState<NotesHomeScreen> createState() => _NotesHomeScreenState();
}

class _NotesHomeScreenState extends ConsumerState<NotesHomeScreen> {
  /// View state — selection, expansion, sort and filters — lives in
  /// [notesHomeUiProvider] rather than in fields here, so each section can
  /// watch only the slice it draws from. Read it for one-shot access inside
  /// callbacks; `build` watches it so the screen still rebuilds on change.
  NotesHomeUiState get _ui => ref.read(notesHomeUiProvider);
  NotesHomeUiController get _uiCtl => ref.read(notesHomeUiProvider.notifier);

  // Cache for note preview strings to avoid jsonDecode on every build.
  // Keyed by "${note.id}_${note.updatedAt}" so stale entries accumulate as
  // notes are edited. Cleared entirely once it exceeds the limit below to
  // prevent unbounded growth without the overhead of LRU bookkeeping.
  static const _previewCacheMaxSize = 500;
  final Map<String, String?> _previewCache = {};

  @override
  void initState() {
    super.initState();
    // Seeded, not forced: the user can clear it like any other filter.
    //
    // The filter now lives in [notesHomeUiProvider] rather than in a field
    // here, and the provider is autoDispose — a second visit starts empty —
    // so the seed has to be written on every mount, not just the first.
    final tagId = widget.initialTagId;
    if (tagId != null) _seedTagFilter({tagId});
  }

  /// Writes the tag filter out of band.
  ///
  /// The filter lives in a provider now, and Riverpod refuses a write from
  /// inside initState or didUpdateWidget — the tree is building at that point
  /// and a notifier change would rebuild it mid-flight. A microtask lands the
  /// write immediately after the current build instead, which is soon enough
  /// that the unfiltered list is never painted.
  void _seedTagFilter(Set<String> tagIds) {
    Future.microtask(() {
      if (!mounted) return;
      _uiCtl.setTagFilter(tagIds);
    });
  }

  /// The active tag filter, so the arriving-from-a-verse-tag path can be
  /// asserted without driving the whole screen's data layer.
  @visibleForTesting
  Set<String> get debugFilterTagIds => _ui.filterTagIds;

  @override
  void didUpdateWidget(NotesHomeScreen old) {
    super.didUpdateWidget(old);
    // Arriving from a second verse tag rebuilds this screen with a new id
    // rather than creating it again, so initState does not run and the list
    // would keep showing the first tag's notes.
    final tagId = widget.initialTagId;
    if (tagId == null || tagId == old.initialTagId) return;
    final next = Set<String>.from(_ui.filterTagIds);
    if (old.initialTagId != null) next.remove(old.initialTagId);
    next.add(tagId);
    _seedTagFilter(next);
  }

  void _clearFilters() => _uiCtl.clearFilters();

  Future<void> _applyFilters() async {
    if (!_ui.hasActiveFilters) {
      _uiCtl.setFilteredNotes(null);
      return;
    }

    try {
      final noteRepository = ref.read(noteRepositoryProvider);
      final userId = ref.read(currentUserIdProvider);

      final results = await noteRepository.searchNotesFiltered(
        userId: userId,
        tagIds: _ui.filterTagIds.isNotEmpty ? _ui.filterTagIds.toList() : null,
        preacherId: _ui.filterPreacherId,
        dateFrom: _ui.filterDateRange?.start.millisecondsSinceEpoch,
        dateTo: _ui.filterDateRange?.end
            .add(const Duration(days: 1))
            .millisecondsSinceEpoch,
        folderId: _ui.selectedFolderId,
      );

      // Convert NoteModel to domain Note using the existing provider's mapping
      final allNotes = ref.read(notesStreamProvider).valueOrNull ?? [];
      final filteredIds = results.map((n) => n.id).toSet();
      if (!mounted) return;
      _uiCtl.setFilteredNotes(
        allNotes.where((n) => filteredIds.contains(n.id)).toList(),
      );
    } catch (e) {
      debugPrint('Failed to apply filters: $e');
    }
  }

  void _enterSelectMode({String? initialNoteId}) =>
      _uiCtl.enterSelectMode(initialNoteId: initialNoteId);

  void _exitSelectMode() => _uiCtl.exitSelectMode();

  void _toggleNoteSelection(String noteId) => _uiCtl.toggleNoteSelected(noteId);

  Future<void> _moveNote(domain.Note note) async {
    final result = await MoveToFolderSheet.show(
      context,
      currentFolderId: note.folderId,
      noteCount: 1,
    );
    if (result == null || !mounted) return;

    try {
      final repository = ref.read(notesRepositoryProvider);
      final moved = await repository.moveNotes([
        note.id,
      ], result.targetFolderId);
      if (!mounted) return;
      if (moved > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n(context).movedToTarget(result.targetFolderName)),
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
    if (_ui.selectedNoteIds.isEmpty) return;

    // Determine current folder for disabling in picker.
    // If all selected notes share the same folder, disable it.
    final notes = ref.read(notesStreamProvider).valueOrNull ?? [];
    final selectedNotes = notes
        .where((n) => _ui.selectedNoteIds.contains(n.id))
        .toList();
    final folderIds = selectedNotes.map((n) => n.folderId).toSet();
    final commonFolderId = folderIds.length == 1 ? folderIds.first : null;

    final result = await MoveToFolderSheet.show(
      context,
      currentFolderId: commonFolderId,
      noteCount: _ui.selectedNoteIds.length,
    );
    if (result == null || !mounted) return;

    try {
      final repository = ref.read(notesRepositoryProvider);
      final moved = await repository.moveNotes(
        _ui.selectedNoteIds.toList(),
        result.targetFolderId,
      );
      if (!mounted) return;
      _exitSelectMode();
      if (moved > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              l10n(context).movedNotesToFolder(moved, result.targetFolderName),
            ),
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
    if (_ui.selectedNoteIds.isEmpty) return;

    final count = _ui.selectedNoteIds.length;
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(l10n(context).moveToTrash),
            content: Text(
              'Move $count selected note${count == 1 ? '' : 's'} to trash?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(l10n(context).actionCancel),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: TextButton.styleFrom(
                  foregroundColor: context.dangerText,
                ),
                child: Text(l10n(context).moveToTrash),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed || !mounted) return;

    final repository = ref.read(notesRepositoryProvider);
    try {
      for (final id in _ui.selectedNoteIds) {
        await repository.trashNote(id);
      }
      if (!mounted) return;
      final deletedCount = _ui.selectedNoteIds.length;
      _exitSelectMode();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Moved $deletedCount note${deletedCount == 1 ? '' : 's'} to trash',
          ),
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

  /// The reader-facing name of a sort option.
  ///
  /// [NotesSortOption.label] is the untranslated fallback; the menu and the
  /// sort control both read from here so they stay in one language.
  String _sortLabel(BuildContext context, NotesSortOption option) =>
      switch (option) {
        NotesSortOption.lastEdited => l10n(context).notesSortLastEdited,
        NotesSortOption.title => l10n(context).notesSortTitle,
        NotesSortOption.createdDate => l10n(context).notesSortCreatedDate,
      };

  List<domain.Note> _sortNotes(List<domain.Note> notes) {
    final sorted = List<domain.Note>.from(notes);
    switch (_ui.sortOption) {
      case NotesSortOption.lastEdited:
        sorted.sort(
          (a, b) => _ui.sortAscending
              ? a.updatedAt.compareTo(b.updatedAt)
              : b.updatedAt.compareTo(a.updatedAt),
        );
        break;
      case NotesSortOption.title:
        sorted.sort(
          (a, b) => _ui.sortAscending
              ? a.title.compareTo(b.title)
              : b.title.compareTo(a.title),
        );
        break;
      case NotesSortOption.createdDate:
        sorted.sort(
          (a, b) => _ui.sortAscending
              ? a.createdAt.compareTo(b.createdAt)
              : b.createdAt.compareTo(a.createdAt),
        );
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
      return l10n(context).yesterday;
    } else if (diff.inDays < 7) {
      return '${diff.inDays} days ago';
    } else {
      return formatShortDate(date);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Subscribes this screen to the view state. The `_ui` getter reads without
    // watching, so this single watch is what keeps the screen in sync; once
    // the sections below become their own widgets they watch for themselves
    // and this can narrow to the slices the shell actually draws.
    ref.watch(notesHomeUiProvider);

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
        appBar: _ui.selecting
            ? _buildSelectionAppBar(context)
            : _buildNormalAppBar(context),
        floatingActionButton: _ui.selecting || _ui.showingTrash
            ? null
            : FloatingActionButton(
                heroTag: null,
                onPressed: () => _showFolderSelectionAndCreateNote(context),
                backgroundColor: AppTheme.brandPurple,
                foregroundColor: AppTheme.onAccent(AppTheme.brandPurple),
                child: const Icon(Icons.add_rounded),
              ),
        body: _ui.showingTrash
            ? _buildTrashSection(context)
            : Column(
                children: [
                  // Folder Section (collapsible accordion)
                  // AnimatedSize with a ceiling rather than AnimatedContainer with a
                  // fixed height: expanding gave 35% of the screen whether there
                  // were twenty folders or none, so an empty list drew ~300pt of
                  // blank space on a tall phone. Now it takes what it needs and
                  // stops at the ceiling.
                  AnimatedSize(
                    duration: context.motion(const Duration(milliseconds: 300)),
                    curve: Curves.easeInOut,
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      key: const ValueKey('folderSection'),
                      constraints: BoxConstraints(
                        maxHeight: _ui.folderSectionExpanded
                            ? MediaQuery.of(context).size.height * 0.35
                            : 48,
                      ),
                      child: const FolderSection(),
                    ),
                  ),

                  // Notes Section (takes remaining space)
                  Expanded(child: _buildNotesSection(context)),
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
      // no-back: the Notes tab root. A branch root has nothing to pop to,
      // so a back button would be a dead control.
      automaticallyImplyLeading: false,
      title: TabTitle(_ui.showingTrash ? 'Trash' : 'Notes'),
      actions: [
        IconButton(
          icon: Icon(
            _ui.showingTrash ? Icons.arrow_back : Icons.delete_outline,
            color: _ui.showingTrash ? colorScheme.onSurface : context.mutedText,
          ),
          tooltip: _ui.showingTrash ? 'Back to Notes' : 'Trash',
          onPressed: () {
            _uiCtl.setShowingTrash(!_ui.showingTrash);
          },
        ),
        if (!_ui.showingTrash)
          IconButton(
            tooltip: l10n(context).actionSearch,
            icon: Icon(
              Icons.search_rounded,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            onPressed: () => context.push(Routes.search),
          ),
        if (!_ui.showingTrash)
          PopupMenuButton<String>(
            icon: Icon(
              Icons.more_vert_rounded,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            onSelected: (value) {
              switch (value) {
                case 'select':
                  _enterSelectMode();
                default:
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(l10n(context).selectedValue(value)),
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
    final count = _ui.selectedNoteIds.length;

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
          icon: Icon(
            Icons.delete_outline,
            color: count > 0 ? context.dangerText : null,
          ),
          tooltip: l10n(context).moveToTrash,
          onPressed: count > 0 ? _deleteSelectedNotes : null,
        ),
      ],
    );
  }

  /// Builds the folder section
  Widget _buildNotesSection(BuildContext context) {
    final notesAsync = ref.watch(notesStreamProvider);

    // Both lookups are derived providers, so they are rebuilt when a person or
    // folder actually changes rather than on every rebuild of this screen.
    final peopleMap = ref.watch(personNamesByIdProvider);
    final folderMap = ref.watch(folderNamesByIdProvider);

    // Smart collection data (only fetch when active)
    final smartNotes = _ui.activeSmartCollection != null
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
          if (_ui.activeSmartCollection != null && smartNotes != null) {
            final smartIds = smartNotes.map((n) => n.id).toSet();
            baseNotes = notes.where((n) => smartIds.contains(n.id)).toList();
          } else if (_ui.hasActiveFilters && _ui.filteredNotes != null) {
            baseNotes = _ui.selectedFolderId == null
                ? _ui.filteredNotes!
                : _ui.filteredNotes!
                      .where((n) => n.folderId == _ui.selectedFolderId)
                      .toList();
          } else {
            baseNotes = _ui.selectedFolderId == null
                ? notes
                : notes
                      .where((n) => n.folderId == _ui.selectedFolderId)
                      .toList();
          }
          final sortedNotes = _sortNotes(baseNotes);

          // Determine header title based on selection
          final String headerTitle;
          if (_ui.activeSmartCollection != null) {
            headerTitle = _ui.activeSmartCollection!.toUpperCase();
          } else if (_ui.selectedFolderId == null) {
            headerTitle = l10n(context).allNotesUpper;
          } else {
            headerTitle = l10n(context).notesInFolderUpper;
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
              if (_ui.filterBarVisible) _buildFilterBar(context),

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
                          final folderName =
                              _ui.selectedFolderId == null &&
                                  note.folderId != null
                              ? folderMap[note.folderId]
                              : null;

                          final isSelected = _ui.selectedNoteIds.contains(
                            note.id,
                          );

                          // Spacing comes from NoteRow's own cardMargin (4
                          // top and bottom). A wrapper here used to add 6
                          // more on each side, putting consecutive rows 20px
                          // apart where every other list leaves 8.
                          return _ui.selecting
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
                                                context,
                                              );
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
                                    onTap: () =>
                                        context.push('/notes/${note.id}'),
                                    onLongPress: () => _enterSelectMode(
                                      initialNoteId: note.id,
                                    ),
                                    actions: [
                                      RowAction(
                                        icon: Icons.checklist_rounded,
                                        label: l10n(context).select,
                                        onSelected: () => _enterSelectMode(
                                          initialNoteId: note.id,
                                        ),
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
        border: Border(bottom: BorderSide(color: context.hairline, width: 1)),
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
        _uiCtl.setFilterBarVisible(!_ui.filterBarVisible);
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _ui.filterBarVisible
                ? Icons.filter_list_rounded
                : Icons.filter_list_off_rounded,
            size: 18,
            color: _ui.hasActiveFilters
                ? AppTheme.brandPurple
                : context.mutedText,
          ),
          if (_ui.hasActiveFilters) ...[
            const SizedBox(width: 2),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: AppTheme.brandPurple,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${_ui.activeFilterCount}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
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
        border: Border(bottom: BorderSide(color: context.hairline, width: 1)),
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
                label: _ui.filterTagIds.isEmpty
                    ? 'Tags'
                    : '${_ui.filterTagIds.length} tag${_ui.filterTagIds.length == 1 ? '' : 's'}',
                selected: _ui.filterTagIds.isNotEmpty,
                onTap: () => _showTagFilterSheet(context, tags),
                accent: AppTheme.brandPurple,
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
                final selectedName = _ui.filterPreacherId != null
                    ? people
                          .where((p) => p.id == _ui.filterPreacherId)
                          .map((p) => p.name)
                          .firstOrNull
                    : null;
                return FilterPill(
                  icon: Icons.person_outlined,
                  label: selectedName ?? 'Preacher',
                  selected: _ui.filterPreacherId != null,
                  onTap: () => _showPreacherFilterSheet(context, people),
                  accent: AppTheme.brandPurple,
                );
              },
            ),
          ),
          const SizedBox(width: 8),

          // Date range chip
          Expanded(
            child: FilterPill(
              icon: Icons.calendar_today_outlined,
              label: _ui.filterDateRange != null
                  ? '${_ui.filterDateRange!.start.day}/${_ui.filterDateRange!.start.month} – ${_ui.filterDateRange!.end.day}/${_ui.filterDateRange!.end.month}'
                  : 'Date',
              selected: _ui.filterDateRange != null,
              onTap: () => _showDateRangeFilter(context),
              accent: AppTheme.brandPurple,
            ),
          ),

          // Clear all
          if (_ui.hasActiveFilters) ...[
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
        border: Border(bottom: BorderSide(color: context.hairline)),
      ),
      child: Row(
        children: [
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
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
                          Icon(
                            Icons.label_off_outlined,
                            size: 40,
                            color: context.hintText,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            l10n(context).noTagsAvailable,
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    ...tags.map((tag) {
                      final isSelected = _ui.filterTagIds.contains(tag.id);
                      return CheckboxListTile(
                        title: Text(tag.name),
                        value: isSelected,
                        activeColor: AppTheme.brandPurple,
                        controlAffinity: ListTileControlAffinity.leading,
                        dense: true,
                        onChanged: (value) {
                          final next = Set<String>.from(_ui.filterTagIds);
                          value == true
                              ? next.add(tag.id)
                              : next.remove(tag.id);
                          setSheetState(() => _uiCtl.setTagFilter(next));
                        },
                      );
                    }),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.brandPurple,
                      ),
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

  void _showPreacherFilterSheet(BuildContext context, List<dynamic> people) {
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
                          Icon(
                            Icons.person_off_outlined,
                            size: 40,
                            color: context.hintText,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            l10n(context).noPeopleAvailable,
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            l10n(context).addPeopleViaNoteDetails,
                            style: TextStyle(
                              color: context.hintText,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    )
                  else ...[
                    // "Any preacher" option to clear
                    ListTile(
                      title: Text(l10n(context).anyPreacher),
                      leading: Icon(
                        _ui.filterPreacherId == null
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                        color: _ui.filterPreacherId == null
                            ? AppTheme.brandPurple
                            : context.mutedText,
                        size: 20,
                      ),
                      dense: true,
                      onTap: () {
                        setSheetState(() {
                          _uiCtl.setPreacherFilter(null);
                        });
                      },
                    ),
                    ...people.map((person) {
                      final isSelected = _ui.filterPreacherId == person.id;
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
                          setSheetState(
                            () => _uiCtl.setPreacherFilter(person.id),
                          );
                        },
                      );
                    }),
                  ],
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.brandPurple,
                      ),
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
              (
                label: l10n(context).last7Days,
                range: DateTimeRange(
                  start: now.subtract(const Duration(days: 7)),
                  end: now,
                ),
              ),
              (
                label: l10n(context).last30Days,
                range: DateTimeRange(
                  start: now.subtract(const Duration(days: 30)),
                  end: now,
                ),
              ),
              (
                label: l10n(context).last90Days,
                range: DateTimeRange(
                  start: now.subtract(const Duration(days: 90)),
                  end: now,
                ),
              ),
              (
                label: l10n(context).thisYear,
                range: DateTimeRange(start: DateTime(now.year), end: now),
              ),
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
                              _ui.filterDateRange == null
                                  ? Icons.radio_button_checked
                                  : Icons.radio_button_unchecked,
                              color: _ui.filterDateRange == null
                                  ? AppTheme.brandPurple
                                  : context.mutedText,
                              size: 20,
                            ),
                            dense: true,
                            onTap: () {
                              setSheetState(
                                () => _uiCtl.setDateRangeFilter(null),
                              );
                            },
                          ),
                          ...presets.map((preset) {
                            final isSelected =
                                _ui.filterDateRange != null &&
                                _ui.filterDateRange!.start.day ==
                                    preset.range.start.day &&
                                _ui.filterDateRange!.start.month ==
                                    preset.range.start.month &&
                                _ui.filterDateRange!.end.day ==
                                    preset.range.end.day;
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
                                setSheetState(
                                  () => _uiCtl.setDateRangeFilter(preset.range),
                                );
                              },
                            );
                          }),
                          // Custom range option
                          ListTile(
                            leading: const Icon(
                              Icons.date_range_outlined,
                              size: 20,
                            ),
                            title: Text(l10n(context).customRange),
                            dense: true,
                            onTap: () async {
                              Navigator.pop(context);
                              final picked = await showDateRangePicker(
                                context: this.context,
                                firstDate: DateTime(2020),
                                lastDate: DateTime.now(),
                                initialDateRange: _ui.filterDateRange,
                                builder: (context, child) {
                                  return Theme(
                                    data: Theme.of(context).copyWith(
                                      colorScheme: Theme.of(context).colorScheme
                                          .copyWith(
                                            primary: AppTheme.brandPurple,
                                          ),
                                    ),
                                    child: child!,
                                  );
                                },
                              );
                              if (picked != null) {
                                _uiCtl.setDateRangeFilter(picked);
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
                        backgroundColor: AppTheme.brandPurple,
                      ),
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
            _sortLabel(context, _ui.sortOption),
            style: theme.textTheme.labelSmall?.copyWith(
              color: AppTheme.brandPurple,
            ),
          ),
          const SizedBox(width: 4),
          Icon(
            _ui.sortAscending
                ? Icons.arrow_upward_rounded
                : Icons.arrow_downward_rounded,
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
                    final isSelected = _ui.sortOption == option;
                    return ListTile(
                      title: Text(_sortLabel(context, option)),
                      leading: Icon(
                        isSelected
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                        color: isSelected
                            ? AppTheme.brandPurple
                            : context.decorativeInk,
                        size: 20,
                      ),
                      dense: true,
                      onTap: () {
                        setSheetState(
                          () => _uiCtl.setSort(
                            option,
                            ascending: _ui.sortAscending,
                          ),
                        );
                      },
                    );
                  }),
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        Text(
                          l10n(context).direction,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const Spacer(),
                        GestureDetector(
                          onTap: () {
                            setSheetState(
                              () => _uiCtl.setSort(
                                _ui.sortOption,
                                ascending: true,
                              ),
                            );
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: _ui.sortAscending
                                  ? AppTheme.brandPurple.withValues(alpha: 0.1)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: _ui.sortAscending
                                    ? AppTheme.brandPurple
                                    : context.hairline,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.arrow_upward_rounded,
                                  size: 14,
                                  color: _ui.sortAscending
                                      ? AppTheme.brandPurple
                                      : context.mutedText,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  l10n(context).asc,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: _ui.sortAscending
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                                    color: _ui.sortAscending
                                        ? AppTheme.brandPurple
                                        : context.mutedText,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () {
                            setSheetState(
                              () => _uiCtl.setSort(
                                _ui.sortOption,
                                ascending: false,
                              ),
                            );
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: !_ui.sortAscending
                                  ? AppTheme.brandPurple.withValues(alpha: 0.1)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: !_ui.sortAscending
                                    ? AppTheme.brandPurple
                                    : context.hairline,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.arrow_downward_rounded,
                                  size: 14,
                                  color: !_ui.sortAscending
                                      ? AppTheme.brandPurple
                                      : context.mutedText,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  l10n(context).desc,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: !_ui.sortAscending
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                                    color: !_ui.sortAscending
                                        ? AppTheme.brandPurple
                                        : context.mutedText,
                                  ),
                                ),
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
                style: TextButton.styleFrom(
                  foregroundColor: context.dangerText,
                ),
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
    switch (_ui.activeSmartCollection) {
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
      (
        name: 'Recently Edited',
        icon: Icons.history_rounded,
        provider: recentlyEditedNotesProvider,
      ),
      (
        name: 'Untagged',
        icon: Icons.label_off_rounded,
        provider: untaggedNotesProvider,
      ),
      (
        name: 'No Activity 30d',
        icon: Icons.hourglass_empty_rounded,
        provider: staleNotesProvider,
      ),
    ];

    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: context.pageGround,
        border: Border(bottom: BorderSide(color: context.hairline, width: 1)),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: collections.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final c = collections[index];
          final isActive = _ui.activeSmartCollection == c.name;
          final countAsync = ref.watch(c.provider);
          final count = countAsync.valueOrNull?.length;

          return GestureDetector(
            onTap: () {
              _uiCtl.setSmartCollection(isActive ? null : c.name);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                // Was Colors.white, which stayed a white pill in dark mode.
                color: isActive ? AppTheme.brandPurple : context.cardSurface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isActive ? AppTheme.brandPurple : context.hairline,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    c.icon,
                    size: 14,
                    color: isActive ? Colors.white : context.mutedText,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    c.name,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: isActive ? Colors.white : context.mutedText,
                    ),
                  ),
                  if (count != null) ...[
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1,
                      ),
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
                          color: isActive ? Colors.white : context.mutedText,
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
                    color: context.mutedText,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    l10n(context).trashEmptyTitle,
                    style: Theme.of(
                      context,
                    ).textTheme.titleMedium?.copyWith(color: context.mutedText),
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
            final title = note.title.isEmpty
                ? domain.Note.untitledLabel
                : note.title;

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
                      icon: Icon(
                        Icons.restore,
                        color: context.successText,
                        size: 20,
                      ),
                      tooltip: l10n(context).restore,
                      onPressed: () => _restoreNote(note.id, title),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.delete_forever,
                        color: context.dangerText,
                        size: 20,
                      ),
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
          content: Text(l10n(context).restoredNamed(title)),
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
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(l10n(context).deletePermanently),
            content: Text(l10n(context).permanentlyDeleteConfirm(title)),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(l10n(context).actionCancel),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: TextButton.styleFrom(
                  foregroundColor: context.dangerText,
                ),
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
          content: Text(l10n(context).permanentlyDeletedNamed(title)),
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

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.note_add_rounded,
              size: 64,
              color: context.mutedText,
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
