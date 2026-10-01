// The screens' half of "a tag still written as #name is not deleted": each
// place that deletes a tag says why it was kept, instead of reporting a
// generic failure or — for Empty Trash — claiming the Trash was emptied.
//
// Real database and repositories, so the refusal comes from the real rule.

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:notify/core/database/sync_database.dart';
import 'package:notify/core/sync/models/note_block_model.dart';
import 'package:notify/core/sync/providers/sync_providers.dart';
import 'package:notify/features/settings/presentation/screens/trash_screen.dart';
import 'package:notify/features/tags/presentation/screens/tag_management_screen.dart';
import 'package:notify/l10n/app_localizations.dart';

const _userId = 'test-user';

void main() {
  late SyncDatabase db;
  late ProviderContainer container;

  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    WidgetController.hitTestWarningShouldBeFatal = true;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    db = SyncDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(overrides: [
      syncDatabaseProvider.overrideWithValue(db),
      currentUserIdProvider.overrideWith((ref) => _userId),
      deviceIdProvider.overrideWith((ref) => 'test-device'),
      sharedPreferencesProvider.overrideWithValue(prefs),
    ]);
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> pump(WidgetTester tester, Widget screen) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: screen,
      ),
    ));
    await settle(tester);
  }

  /// A tag named [name], and a live note whose text writes `#name`.
  Future<String> writtenTag(WidgetTester tester, String name,
          {bool trashed = false}) async =>
      (await tester.runAsync(() async {
        final tags = container.read(tagRepositoryProvider);
        final tag = await tags.createTag(userId: _userId, name: name);
        final folder = await container
            .read(folderRepositoryProvider)
            .createFolder(name: 'Sermons', userId: _userId);
        final note = await container.read(noteRepositoryProvider).createNote(
            folderId: folder.id, userId: _userId, title: 'Sunday');
        await container.read(noteBlockRepositoryProvider).createBlock(
              noteId: note.id,
              blockType: BlockType.paragraph,
              content: {'text': 'by #$name alone'},
              orderIndex: 0,
            );
        if (trashed) await tags.trashTag(tag.id);
        return tag.id;
      }))!;

  /// Opens the popup menu and waits out its animation. Its items fade in one
  /// after another, and the last becomes tappable only on a later frame, so
  /// this pumps frame by frame rather than jumping the clock once.
  Future<void> openMenu(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.more_vert));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// Dialogs animate in too.
  Future<void> waitForDialog(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 500));
    await settle(tester);
  }

  Future<bool> stillLive(WidgetTester tester, String id) async =>
      (await tester.runAsync(() async =>
          (await container.read(tagRepositoryProvider).getTagById(id))!
              .deleted ==
          0))!;

  const message =
      '#faith is still written in 1 note. Remove it from the text to delete '
      'the tag.';

  testWidgets('the Tags screen explains why the tag was kept', (tester) async {
    final id = await writtenTag(tester, 'faith');

    await pump(tester, const TagManagementScreen());
    await openMenu(tester);
    await tester.tap(find.widgetWithText(PopupMenuItem<String>, 'Delete'));
    await waitForDialog(tester);
    await tester.tap(find.descendant(
        of: find.byType(AlertDialog), matching: find.text('Delete')));
    await settle(tester);

    expect(find.text(message), findsOneWidget);
    expect(await stillLive(tester, id), isTrue);
  });

  testWidgets('the Tags screen explains why a merge was refused',
      (tester) async {
    final id = await writtenTag(tester, 'faith');
    await tester.runAsync(() => container
        .read(tagRepositoryProvider)
        .createTag(userId: _userId, name: 'belief'));

    await pump(tester, const TagManagementScreen());
    await tester.tap(find.descendant(
        of: find.widgetWithText(ListTile, 'faith'),
        matching: find.byIcon(Icons.more_vert)));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.tap(find.widgetWithText(PopupMenuItem<String>, 'Merge into...'));
    await waitForDialog(tester);
    await tester.tap(find.descendant(
        of: find.byType(BottomSheet),
        matching: find.widgetWithText(ListTile, 'belief')));
    await waitForDialog(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Merge'));
    await settle(tester);

    expect(
        find.text('#faith is still written in 1 note. Remove it from the '
            'text to merge the tag.'),
        findsOneWidget);
    expect(await stillLive(tester, id), isTrue);
  });

  testWidgets('deleting it from Trash explains why it was kept',
      (tester) async {
    final id = await writtenTag(tester, 'faith', trashed: true);

    await pump(tester, const TrashScreen());
    await tester.tap(find.byTooltip('Delete permanently'));
    await waitForDialog(tester);
    await tester.tap(find.descendant(
        of: find.byType(AlertDialog), matching: find.text('Delete')));
    await settle(tester);

    expect(find.text(message), findsOneWidget);
    expect(find.text('Permanently deleted'), findsNothing);
    expect(await stillLive(tester, id), isTrue);
  });

  testWidgets('Empty Trash says a tag was kept instead of "Trash emptied"',
      (tester) async {
    final id = await writtenTag(tester, 'faith', trashed: true);

    await pump(tester, const TrashScreen());
    await openMenu(tester);
    await tester.tap(find.widgetWithText(PopupMenuItem<String>, 'Empty trash'));
    await waitForDialog(tester);
    // The dialog's title says "Empty trash" too; tap its button.
    await tester.tap(find.widgetWithText(TextButton, 'Empty trash'));
    await settle(tester);

    expect(
        find.text('1 tag was kept because notes still write it as a '
            'hashtag.'),
        findsOneWidget);
    expect(find.text('Trash emptied'), findsNothing);
    expect(await stillLive(tester, id), isTrue);
  });
}
