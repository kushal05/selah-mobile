// The notes list is filtered and sorted once per change, not once per rebuild.
//
// This pipeline ran inside `build()`: every rebuild of the notes screen copied
// the whole collection and sorted it again, whether or not anything affecting
// the order had changed. Expanding a folder re-sorted every note the user owns.
//
// The provider caches on its inputs, so the two things worth pinning are that
// it still produces the right order, and that reading it twice without a change
// does not recompute.

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:notify/features/notes/domain/models/note.dart' as domain;
import 'package:notify/features/notes/domain/models/notes_sort_option.dart';
import 'package:notify/features/notes/presentation/providers/database_provider.dart';
import 'package:notify/features/notes/presentation/providers/notes_home_ui_state.dart';
import 'package:notify/features/notes/presentation/providers/visible_notes_provider.dart';

domain.Note _note(String id, String title, {int updated = 0, int created = 0}) =>
    domain.Note.create(id: id, title: title).copyWith(
      updatedAt: DateTime.fromMillisecondsSinceEpoch(updated),
      createdAt: DateTime.fromMillisecondsSinceEpoch(created),
    );

void main() {
  group('sortNotes', () {
    final notes = [
      _note('a', 'banana', updated: 30, created: 1),
      _note('b', 'Apple', updated: 10, created: 3),
      _note('c', 'cherry', updated: 20, created: 2),
    ];

    test('by title, case-insensitively', () {
      // The whole reason this does not use String.compareTo: that orders by
      // UTF-16 code unit, so "Apple" would sort after "banana".
      final sorted = sortNotes(notes, NotesSortOption.title, ascending: true);
      expect(sorted.map((n) => n.title), ['Apple', 'banana', 'cherry']);
    });

    test('by last edited, newest first by default', () {
      final sorted =
          sortNotes(notes, NotesSortOption.lastEdited, ascending: false);
      expect(sorted.map((n) => n.id), ['a', 'c', 'b']);
    });

    test('by created date, ascending', () {
      final sorted =
          sortNotes(notes, NotesSortOption.createdDate, ascending: true);
      expect(sorted.map((n) => n.id), ['a', 'c', 'b']);
    });

    test('does not mutate the list it was given', () {
      final input = [...notes];
      sortNotes(input, NotesSortOption.title, ascending: true);
      expect(input.map((n) => n.id), ['a', 'b', 'c']);
    });
  });

  group('visibleNotesProvider', () {
    ProviderContainer containerWith(List<domain.Note> notes) {
      final c = ProviderContainer(overrides: [
        notesStreamProvider.overrideWith((ref) => Stream.value(notes)),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    test('recomputes only when an input changes', () async {
      final c = containerWith([
        _note('a', 'banana', updated: 2),
        _note('b', 'apple', updated: 1),
      ]);
      await c.read(notesStreamProvider.future);

      final first = c.read(visibleNotesProvider).valueOrNull;
      final second = c.read(visibleNotesProvider).valueOrNull;
      // Identical instance: the second read came from the cache rather than
      // sorting again. Worth stating, but it cannot fail on its own — Riverpod
      // would have to stop caching for that. The regression this work actually
      // guards against is structural, and the test below is the one that
      // catches it.
      expect(identical(first, second), isTrue);

      c.read(notesHomeUiProvider.notifier)
          .setSort(NotesSortOption.title, ascending: true);
      final third = c.read(visibleNotesProvider).valueOrNull;
      expect(identical(first, third), isFalse,
          reason: 'changing the sort must recompute');
      expect(third!.map((n) => n.title), ['apple', 'banana']);
    });
  });

  test('the screen does not sort in build() again', () {
    // The defect was a full copy-and-sort of every note inside the notes
    // screen's build(). Riverpod caching only helps while the pipeline stays
    // in the provider, so this asserts where it lives rather than how fast it
    // is — a timing assertion here would be flaky and would not say why.
    final screen = File(
      'lib/features/notes/presentation/screens/notes_home_screen.dart',
    ).readAsStringSync();

    expect(screen.contains('visibleNotesProvider'), isTrue,
        reason: 'the screen must read the derived provider');
    expect(RegExp(r'\.sort\(').hasMatch(screen), isFalse,
        reason: 'no list sort belongs in this screen; put it in a provider');
    expect(screen.contains('_sortNotes('), isFalse,
        reason: 'the in-build sort helper is gone — do not bring it back');
  });
}
