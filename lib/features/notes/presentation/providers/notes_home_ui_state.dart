import 'package:flutter/material.dart' show DateTimeRange;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/note.dart' as domain;
import '../../domain/models/notes_sort_option.dart';

/// The Notes screen's own view state — what is selected, expanded, filtered
/// and sorted.
///
/// This lived as a dozen fields on `_NotesHomeScreenState`, mutated through
/// `setState`. That meant every change rebuilt the whole 2,000-line screen:
/// opening the sort menu rebuilt the folder tree, and expanding a folder
/// rebuilt the note list. Holding it here lets each section watch only the
/// slice it draws from, so a sort change no longer touches the folder tree.
class NotesHomeUiState {
  final String? selectedFolderId;
  final Set<String> expandedFolders;
  final NotesSortOption sortOption;
  final bool sortAscending;
  final bool folderSectionExpanded;
  final bool selecting;
  final Set<String> selectedNoteIds;
  final String? activeSmartCollection;
  final bool showingTrash;

  // Filters
  final bool filterBarVisible;
  final Set<String> filterTagIds;
  final String? filterPreacherId;
  final DateTimeRange? filterDateRange;

  /// Result of the last filter query, or null when no filter is applied.
  /// Populated asynchronously by the screen, since it needs a repository.
  final List<domain.Note>? filteredNotes;

  const NotesHomeUiState({
    this.selectedFolderId,
    this.expandedFolders = const {},
    this.sortOption = NotesSortOption.lastEdited,
    this.sortAscending = false,
    this.folderSectionExpanded = false,
    this.selecting = false,
    this.selectedNoteIds = const {},
    this.activeSmartCollection,
    this.showingTrash = false,
    this.filterBarVisible = true,
    this.filterTagIds = const {},
    this.filterPreacherId,
    this.filterDateRange,
    this.filteredNotes,
  });

  bool get hasActiveFilters =>
      filterTagIds.isNotEmpty ||
      filterPreacherId != null ||
      filterDateRange != null;

  int get activeFilterCount =>
      (filterTagIds.isNotEmpty ? 1 : 0) +
      (filterPreacherId != null ? 1 : 0) +
      (filterDateRange != null ? 1 : 0);

  /// `null` sentinels are ambiguous for the nullable fields, so each takes a
  /// `clear*` flag rather than overloading null to mean "unchanged".
  NotesHomeUiState copyWith({
    String? selectedFolderId,
    bool clearSelectedFolderId = false,
    Set<String>? expandedFolders,
    NotesSortOption? sortOption,
    bool? sortAscending,
    bool? folderSectionExpanded,
    bool? selecting,
    Set<String>? selectedNoteIds,
    String? activeSmartCollection,
    bool clearActiveSmartCollection = false,
    bool? showingTrash,
    bool? filterBarVisible,
    Set<String>? filterTagIds,
    String? filterPreacherId,
    bool clearFilterPreacherId = false,
    DateTimeRange? filterDateRange,
    bool clearFilterDateRange = false,
    List<domain.Note>? filteredNotes,
    bool clearFilteredNotes = false,
  }) {
    return NotesHomeUiState(
      selectedFolderId: clearSelectedFolderId
          ? null
          : (selectedFolderId ?? this.selectedFolderId),
      expandedFolders: expandedFolders ?? this.expandedFolders,
      sortOption: sortOption ?? this.sortOption,
      sortAscending: sortAscending ?? this.sortAscending,
      folderSectionExpanded:
          folderSectionExpanded ?? this.folderSectionExpanded,
      selecting: selecting ?? this.selecting,
      selectedNoteIds: selectedNoteIds ?? this.selectedNoteIds,
      activeSmartCollection: clearActiveSmartCollection
          ? null
          : (activeSmartCollection ?? this.activeSmartCollection),
      showingTrash: showingTrash ?? this.showingTrash,
      filterBarVisible: filterBarVisible ?? this.filterBarVisible,
      filterTagIds: filterTagIds ?? this.filterTagIds,
      filterPreacherId: clearFilterPreacherId
          ? null
          : (filterPreacherId ?? this.filterPreacherId),
      filterDateRange: clearFilterDateRange
          ? null
          : (filterDateRange ?? this.filterDateRange),
      filteredNotes: clearFilteredNotes
          ? null
          : (filteredNotes ?? this.filteredNotes),
    );
  }
}

class NotesHomeUiController extends StateNotifier<NotesHomeUiState> {
  NotesHomeUiController() : super(const NotesHomeUiState());

  void selectFolder(String? id) => state = id == null
      ? state.copyWith(
          clearSelectedFolderId: true,
          clearActiveSmartCollection: true,
        )
      : state.copyWith(selectedFolderId: id, clearActiveSmartCollection: true);

  void toggleFolderExpanded(String id) {
    final next = Set<String>.from(state.expandedFolders);
    next.contains(id) ? next.remove(id) : next.add(id);
    state = state.copyWith(expandedFolders: next);
  }

  void toggleFolderSection() => state = state.copyWith(
    folderSectionExpanded: !state.folderSectionExpanded,
  );

  void setSort(NotesSortOption option, {required bool ascending}) =>
      state = state.copyWith(sortOption: option, sortAscending: ascending);

  void setSmartCollection(String? name) => name == null
      ? state = state.copyWith(clearActiveSmartCollection: true)
      : state = state.copyWith(
          activeSmartCollection: name,
          clearSelectedFolderId: true,
        );

  void setShowingTrash(bool showing) =>
      state = state.copyWith(showingTrash: showing);

  void enterSelectMode({String? initialNoteId}) => state = state.copyWith(
    selecting: true,
    selectedNoteIds: initialNoteId == null ? const {} : {initialNoteId},
  );

  void exitSelectMode() =>
      state = state.copyWith(selecting: false, selectedNoteIds: const {});

  void toggleNoteSelected(String noteId) {
    final next = Set<String>.from(state.selectedNoteIds);
    next.contains(noteId) ? next.remove(noteId) : next.add(noteId);
    // Leaving the last note deselected drops out of select mode, which is what
    // the row-level tap handler did before.
    state = next.isEmpty
        ? state.copyWith(selecting: false, selectedNoteIds: const {})
        : state.copyWith(selectedNoteIds: next);
  }

  void setFilterBarVisible(bool visible) =>
      state = state.copyWith(filterBarVisible: visible);

  void setTagFilter(Set<String> tagIds) =>
      state = state.copyWith(filterTagIds: tagIds);

  void setPreacherFilter(String? personId) => personId == null
      ? state = state.copyWith(clearFilterPreacherId: true)
      : state = state.copyWith(filterPreacherId: personId);

  void setDateRangeFilter(DateTimeRange? range) => range == null
      ? state = state.copyWith(clearFilterDateRange: true)
      : state = state.copyWith(filterDateRange: range);

  void setFilteredNotes(List<domain.Note>? notes) => notes == null
      ? state = state.copyWith(clearFilteredNotes: true)
      : state = state.copyWith(filteredNotes: notes);

  void clearFilters() => state = state.copyWith(
    filterTagIds: const {},
    clearFilterPreacherId: true,
    clearFilterDateRange: true,
    clearFilteredNotes: true,
    filterBarVisible: false,
  );
}

/// Scoped to the Notes screen.
///
/// `autoDispose` frees the state if the screen is ever torn down, but do not
/// read it as a per-visit reset: the Notes tab is a `StatefulShellRoute
/// .indexedStack` branch, so the screen stays mounted and keeps this watched
/// for the life of the process. Selection therefore survives a tab switch —
/// which is what the reader expects — and a folder deleted by sync while the
/// user was elsewhere leaves `selectedFolderId` pointing at nothing. Clearing
/// that belongs with whatever observes the folder list, not here.
final notesHomeUiProvider =
    StateNotifierProvider.autoDispose<NotesHomeUiController, NotesHomeUiState>(
      (ref) => NotesHomeUiController(),
    );
