// Two things the notes list says about what you are looking at.
//
// 1. The smart collections — Recently Edited, Untagged, No Activity 30d — used
//    to occupy a row of their own above the section header, always on screen.
//    They are chips that choose which notes to show, which is what the filter
//    bar is for, so they moved into it. Two stacked rows became one scrollable
//    one and the list gained back 44pt.
//
// 2. The header said "Notes in Folder", which tells you that you are in a
//    folder but not which one. It names the folder now.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:notify/core/sync/models/folder_model.dart';
import 'package:notify/core/services/user_facing_error.dart';
import 'package:notify/core/sync/providers/sync_providers.dart';
import 'package:notify/core/theme/app_theme.dart';
import 'package:notify/l10n/l10n.dart';
import 'package:notify/features/notes/presentation/providers/database_provider.dart';
import 'package:notify/features/notes/presentation/providers/notes_home_ui_state.dart';
import 'package:notify/features/notes/presentation/providers/smart_collection.dart';
import 'package:notify/features/notes/presentation/providers/visible_notes_provider.dart';
import 'package:notify/features/notes/domain/models/note.dart' as domain;
import 'package:notify/features/notes/presentation/screens/notes_home_screen.dart';
import 'package:notify/shared/widgets/filter_pill.dart';
import 'package:notify/shared/widgets/skeletons/list_tile_skeleton.dart';

const _collections = ['Recently Edited', 'Untagged', 'No Activity 30d'];

FolderModel _folder(String id, String name) => FolderModel(
  id: id,
  userId: 'u1',
  name: name,
  updatedAt: 0,
  version: 1,
  deleted: 0,
  createdAt: 0,
);

/// Pumps the real screen. [openFilters] opens the bar the way the button does;
/// [selectFolder] selects one the way tapping a folder row does.
Future<ProviderContainer> _pump(
  WidgetTester tester, {
  bool openFilters = false,
  String? selectFolder,
  List<FolderModel> folders = const [],
  double width = 1400,
  Stream<List<String>> Function()? untagged,
}) async {
  // Wide enough to hold all six pills, so nothing under test is off-screen.
  tester.view.physicalSize = Size(width * 3, 1800);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();

  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      notesStreamProvider.overrideWith((ref) => Stream.value(const [])),
      noteFoldersStreamProvider.overrideWith((ref) => Stream.value(folders)),
      peopleStreamProvider.overrideWith((ref) => Stream.value(const [])),
      tagsStreamProvider.overrideWith((ref) => Stream.value(const [])),
      // The collections answer, as they do on a device. Without these the
      // real queries cannot run here, and the header used to show a count
      // anyway — taken from every note, before the collection had answered.
      // One assertion below was passing on exactly that.
      recentlyEditedNoteIdsProvider.overrideWith((ref) => Stream.value(const [])),
      untaggedNoteIdsProvider.overrideWith(
          (ref) => untagged?.call() ?? Stream.value(const [])),
      staleNoteIdsProvider.overrideWith((ref) => Stream.value(const [])),
    ],
  );
  addTearDown(container.dispose);

  final ui = container.read(notesHomeUiProvider.notifier);
  if (openFilters) ui.setFilterBarVisible(true);
  if (selectFolder != null) ui.selectFolder(selectFolder);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const NotesHomeScreen(),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump();
  return container;
}

void main() {
  group('the smart collections live in the filter bar', () {
    testWidgets('and are not on screen until it is opened', (tester) async {
      // The whole point of the move: they no longer take a row of their own on
      // every visit to Notes.
      await _pump(tester);

      for (final name in _collections) {
        expect(find.text(name), findsNothing, reason: '$name should be hidden');
      }
    });

    testWidgets('and all three appear once it is', (tester) async {
      await _pump(tester, openFilters: true);

      for (final name in _collections) {
        expect(find.text(name), findsOneWidget);
      }
    });

    testWidgets('as FilterPills, not a fourth hand-rolled chip', (tester) async {
      // They were their own Container-and-GestureDetector with `Colors.white`
      // hardcoded for the selected label, so a selected collection drew white on
      // purple in both themes.
      await _pump(tester, openFilters: true);

      for (final name in _collections) {
        expect(
          find.ancestor(of: find.text(name), matching: find.byType(FilterPill)),
          findsOneWidget,
          reason: '$name should be drawn by the shared pill',
        );
      }
    });

    testWidgets('before the filters, which are a different question',
        (tester) async {
      await _pump(tester, openFilters: true);

      final pills = tester
          .widgetList<FilterPill>(find.byType(FilterPill))
          .map((p) => p.label)
          .toList();

      expect(pills, [..._collections, 'Tags', 'Preacher', 'Date']);
    });

    testWidgets('tapping one selects it, tapping again clears it',
        (tester) async {
      // Choosing a collection is how you narrow the list; tapping the active one
      // is the only way back to every note.
      final container = await _pump(tester, openFilters: true);
      NotesHomeUiState state() => container.read(notesHomeUiProvider);

      expect(state().activeSmartCollection, isNull);

      await tester.tap(find.text('Untagged'));
      await tester.pump();
      expect(state().activeSmartCollection, SmartCollection.untagged);

      await tester.tap(find.text('Untagged'));
      await tester.pump();
      expect(state().activeSmartCollection, isNull,
          reason: 'a second tap must turn it off');
    });

    testWidgets('and selecting one does not register as an active filter',
        (tester) async {
      // hasActiveFilters drives the tag/preacher/date query and the branch in
      // visibleNotesProvider. A collection replaces that result rather than
      // narrowing it, so folding it in here would run a query with no criteria.
      final container = await _pump(tester, openFilters: true);

      await tester.tap(find.text('Recently Edited'));
      await tester.pump();

      final state = container.read(notesHomeUiProvider);
      expect(state.activeSmartCollection, SmartCollection.recentlyEdited);
      expect(state.hasActiveFilters, isFalse);
      expect(state.activeFilterCount, 0);
    });
  });

  // The header shouts its title and appends the count: `ALL NOTES (0)`. Worth
  // stating once, because searching for the natural casing finds nothing and
  // a findsNothing assertion written that way passes without testing anything —
  // which is how the last test in this group first "passed".
  String header(String title, int count) => '${title.toUpperCase()} ($count)';

  group('a smart collection, keyed by its enum', () {
    // A plain test: it pumps no widgets, and provider timers outliving the
    // tree trip testWidgets' teardown check without saying anything about
    // the narrowing.
    test('narrows the list to its own notes', () async {
      // The wiring the string ids put at risk: state holds the enum, the
      // filter looks the collection's notes up from it, and only those show.
      // Under the old `_ => null` fallthrough a name that failed to match
      // showed every note — so this asserts the narrowing, not just the chip.
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        notesStreamProvider.overrideWith((ref) => Stream.value([
          domain.Note.create(id: 'a', title: 'Tagged sermon'),
          domain.Note.create(id: 'b', title: 'Loose thought'),
        ])),
        untaggedNoteIdsProvider.overrideWith(
          (ref) => Stream.value(const ['b']),
        ),
      ]);
      addTearDown(container.dispose);
      // Held open the way the screen holds it: the collection is autoDispose,
      // and a bare read would be disposed before the filter looks at it.
      final held = container.listen(visibleNotesProvider, (_, _) {});
      addTearDown(held.close);
      await container.read(notesStreamProvider.future);

      container
          .read(notesHomeUiProvider.notifier)
          .setSmartCollection(SmartCollection.untagged);
      await container.read(untaggedNoteIdsProvider.future);

      final visible = container.read(visibleNotesProvider).valueOrNull!;
      expect(visible.map((n) => n.id), ['b']);
    });

    for (final c in SmartCollection.values) {
      testWidgets('${c.name} has a label of its own', (tester) async {
        // Display text comes from the catalogue, so it can be translated
        // without touching which notes the collection holds.
        late String label;
        await tester.pumpWidget(MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(builder: (context) {
            label = c.label(context);
            return const SizedBox();
          }),
        ));
        expect(label, isNotEmpty);
        expect(
          SmartCollection.values
              .where((o) => o != c)
              .map((o) => o.name),
          isNot(contains(label)),
          reason: 'the label is display text, not an identifier',
        );
      });
    }
  });

  group('while a chosen collection is loading or has failed', () {
    // A collection is chosen from a chip in the filter bar. If its loading
    // state blanked the screen the way the notes' own first load does, the bar
    // would vanish from under the finger — and if the query then failed, there
    // would be no chip left to tap to get out. The header and bar stay; only
    // the list shows the wait or the error.
    final bar = find.widgetWithText(FilterPill, 'Untagged');

    testWidgets('the header and filter bar stay, and only the list waits',
        (tester) async {
      final pending = StreamController<List<String>>();
      addTearDown(pending.close);
      await _pump(tester, openFilters: true, untagged: () => pending.stream);

      await tester.tap(bar);
      await tester.pump();

      expect(bar, findsOneWidget, reason: 'the filter bar must not vanish');
      expect(find.text('UNTAGGED'), findsOneWidget,
          reason: 'heading, without a count it does not have yet');
      expect(find.textContaining('UNTAGGED ('), findsNothing,
          reason: 'any number now would be a guess — it used to be all notes');
      expect(find.byType(ListTileSkeletonList), findsOneWidget);
    });

    testWidgets('a failure shows in the list, and the chip still lets go',
        (tester) async {
      final error = StateError('query failed');
      final container = await _pump(
        tester,
        openFilters: true,
        untagged: () => Stream.error(error),
      );

      await tester.tap(bar);
      await tester.pump();
      await tester.pump();

      expect(find.text(UserFacingError.forLoad(error)), findsOneWidget);
      expect(bar, findsOneWidget, reason: 'the way out has to still be there');

      await tester.tap(bar);
      await tester.pump();

      expect(container.read(notesHomeUiProvider).activeSmartCollection, isNull);
      expect(find.text(UserFacingError.forLoad(error)), findsNothing);
    });
  });

  group('the header names the folder you are in', () {
    testWidgets('instead of saying "Notes in Folder"', (tester) async {
      await _pump(
        tester,
        selectFolder: 'f1',
        folders: [_folder('f1', 'Sunday Sermons')],
      );

      expect(find.text(header('Sunday Sermons', 0)), findsOneWidget);
      expect(find.textContaining('NOTES IN FOLDER'), findsNothing);
    });

    testWidgets('and still says All Notes when none is selected',
        (tester) async {
      await _pump(tester, folders: [_folder('f1', 'Sunday Sermons')]);

      expect(find.text(header('All Notes', 0)), findsOneWidget);
    });

    testWidgets('falling back to the generic wording for an unknown folder',
        (tester) async {
      // folderNamesById comes from a stream: it is empty on the first frame, and
      // a folder deleted on another device can disappear from it while still
      // selected here. Neither case should leave the header blank.
      await _pump(tester, selectFolder: 'gone', folders: const []);

      expect(find.text(header('Notes in Folder', 0)), findsOneWidget);
    });

    testWidgets('and an active collection still wins over the folder name',
        (tester) async {
      // Choosing a collection clears the folder, so naming the folder here would
      // describe a selection that is no longer in effect.
      final container = await _pump(
        tester,
        openFilters: true,
        selectFolder: 'f1',
        folders: [_folder('f1', 'Sunday Sermons')],
      );

      await tester.tap(find.text('Untagged'));
      await tester.pump();

      expect(container.read(notesHomeUiProvider).selectedFolderId, isNull);
      expect(find.textContaining('SUNDAY SERMONS'), findsNothing,
          reason: 'the folder is no longer selected, so it must not be named');
      expect(find.text(header('Untagged', 0)), findsOneWidget);
    });
  });
}
