import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/note.dart' as domain;
import '../../domain/models/notes_sort_option.dart';
import 'database_provider.dart';
import 'notes_home_ui_state.dart';

/// The notes the list should draw, filtered and sorted.
///
/// This ran inside `build()`: every rebuild of the notes screen copied the
/// whole collection and sorted it again, whether or not anything that affects
/// the order had changed. Opening the sort menu, expanding a folder, typing in
/// the search box — each one re-sorted every note the user owns.
///
/// As a provider it recomputes only when one of its inputs changes, and
/// Riverpod hands the cached list to every other rebuild. The inputs are named
/// explicitly below rather than watched as a whole `NotesHomeUiState`, because
/// that object also carries selection and expansion state — watching it whole
/// would recompute the sort when the user ticks a checkbox.
final visibleNotesProvider = Provider<AsyncValue<List<domain.Note>>>((ref) {
  final notesAsync = ref.watch(notesStreamProvider);

  final smartCollection =
      ref.watch(notesHomeUiProvider.select((s) => s.activeSmartCollection));
  final folderId =
      ref.watch(notesHomeUiProvider.select((s) => s.selectedFolderId));
  final hasFilters =
      ref.watch(notesHomeUiProvider.select((s) => s.hasActiveFilters));
  final filtered =
      ref.watch(notesHomeUiProvider.select((s) => s.filteredNotes));
  final sortOption =
      ref.watch(notesHomeUiProvider.select((s) => s.sortOption));
  final ascending =
      ref.watch(notesHomeUiProvider.select((s) => s.sortAscending));

  // Only subscribed to while that collection is the active one, so the three
  // smart-collection queries do not run for a user who never opens them.
  //
  // Keyed by the enum, not by its English name. The string version ended in
  // `_ => null`, so a name that did not match — a typo, or a translation —
  // fell through silently and showed every note.
  final collection =
      smartCollection == null ? null : ref.watch(smartCollection.noteIds);

  // A chosen collection that has not answered yet is *loading*, and one whose
  // query failed is an *error* — neither is "every note". Both used to fall
  // through to the branches below, which put the whole notebook under a
  // heading that said Untagged until the query landed, and kept it there for
  // good if the query failed. Once a collection has a value, later re-runs
  // (after an edit) keep showing it, so following edits does not flash this.
  if (collection != null && !collection.hasValue) {
    return collection.hasError
        ? AsyncError(collection.error!, collection.stackTrace!)
        : const AsyncLoading();
  }
  final smartIds = collection?.requireValue.toSet();

  return notesAsync.whenData((notes) {
    final List<domain.Note> base;
    if (smartIds != null) {
      base = notes.where((n) => smartIds.contains(n.id)).toList();
    } else if (hasFilters && filtered != null) {
      base = folderId == null
          ? filtered
          : filtered.where((n) => n.folderId == folderId).toList();
    } else {
      base = folderId == null
          ? notes
          : notes.where((n) => n.folderId == folderId).toList();
    }

    return sortNotes(base, sortOption, ascending: ascending);
  });
});

/// Sorts [notes] by [option]. Pure, so it can be tested without a container
/// and reused by anything else that needs the same order.
List<domain.Note> sortNotes(
  List<domain.Note> notes,
  NotesSortOption option, {
  required bool ascending,
}) {
  final sorted = List<domain.Note>.from(notes);
  switch (option) {
    case NotesSortOption.lastEdited:
      sorted.sort((a, b) => ascending
          ? a.updatedAt.compareTo(b.updatedAt)
          : b.updatedAt.compareTo(a.updatedAt));
    case NotesSortOption.title:
      // compareNoteTitles, not String.compareTo: the latter orders by UTF-16
      // code unit, which puts every capital before every lowercase.
      sorted.sort((a, b) => ascending
          ? compareNoteTitles(a.title, b.title)
          : compareNoteTitles(b.title, a.title));
    case NotesSortOption.createdDate:
      sorted.sort((a, b) => ascending
          ? a.createdAt.compareTo(b.createdAt)
          : b.createdAt.compareTo(a.createdAt));
  }
  return sorted;
}
