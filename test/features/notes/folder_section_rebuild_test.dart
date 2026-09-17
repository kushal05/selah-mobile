// The point of splitting notes_home_screen.dart is rebuild scoping, so this
// asserts it on the real widget rather than on a duplicated selector.
//
// Everything used to sit in one State class, so any setState — opening the
// sort menu, toggling a filter — rebuilt the folder tree too, re-running the
// flatten and its note-count roll-up over every folder the user has.
//
// How this measures a rebuild: a widget that rebuilds constructs new child
// Widget instances. If FolderSection did not rebuild, the element tree still
// holds the *same* FolderRow instance, so `identical` is true. That catches a
// stray `ref.watch` inside a helper, which a test of the selector alone
// cannot.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:notify/core/sync/models/folder_model.dart';
import 'package:notify/core/sync/providers/sync_providers.dart';
import 'package:notify/core/theme/app_theme.dart';
import 'package:notify/l10n/l10n.dart';
import 'package:notify/features/notes/domain/models/notes_sort_option.dart';
import 'package:notify/features/notes/presentation/providers/database_provider.dart';
import 'package:notify/features/notes/presentation/providers/notes_home_ui_state.dart';
import 'package:notify/features/notes/presentation/widgets/folder_section.dart';
import 'package:notify/shared/widgets/lists/folder_row.dart';

FolderModel _folder(String id) => FolderModel(
  id: id,
  name: id,
  type: 'note',
  userId: 'u1',
  updatedAt: 0,
  createdAt: 0,
  version: 1,
  deleted: 0,
);

void main() {
  testWidgets('sort and filter changes do not rebuild the folder tree', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        noteFoldersStreamProvider.overrideWith(
          (ref) => Stream.value([_folder('Sermons'), _folder('Study')]),
        ),
        notesStreamProvider.overrideWith((ref) => Stream.value(const [])),
      ],
    );
    addTearDown(container.dispose);

    // The tree only renders its rows once the section is open.
    container.read(notesHomeUiProvider.notifier).toggleFolderSection();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: FolderSection()),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    FolderRow firstRow() =>
        tester.widget<FolderRow>(find.byType(FolderRow).first);

    expect(find.byType(FolderRow), findsWidgets, reason: 'the tree rendered');
    final before = firstRow();

    final ctl = container.read(notesHomeUiProvider.notifier);

    // None of these are drawn by the folder tree.
    ctl.setSort(NotesSortOption.title, ascending: true);
    await tester.pump();
    ctl.setFilterBarVisible(false);
    await tester.pump();
    ctl.setShowingTrash(true);
    await tester.pump();

    expect(
      identical(firstRow(), before),
      isTrue,
      reason: 'sort, filter and trash changes must not rebuild the folder tree',
    );

    // One that is.
    ctl.selectFolder('Sermons');
    await tester.pump();

    expect(
      identical(firstRow(), before),
      isFalse,
      reason: 'selecting a folder must rebuild it',
    );
  });
}
