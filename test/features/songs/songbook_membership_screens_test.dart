// The screens' half of multi-songbook songs. The repository tests pin what
// each query and write does; these pin that the screens call them. Without
// these, the editor could stop saving links, the home list could go back to
// reading folder_id alone, or the detail screen could drop its songbook chips,
// and every other test would still pass — a mutation sweep showed exactly that.
//
// Real database, real repositories: the point is the wiring between them.

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:notify/core/database/sync_database.dart';
import 'package:notify/core/sync/providers/sync_providers.dart';
import 'package:notify/features/songs/presentation/screens/add_song_screen.dart';
import 'package:notify/features/songs/presentation/screens/song_detail_screen.dart';
import 'package:notify/features/songs/presentation/screens/songs_home_screen.dart';
import 'package:notify/l10n/app_localizations.dart';

const _userId = 'test-user';

void main() {
  late SyncDatabase db;
  late ProviderContainer container;

  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    // A tap that misses (a sheet still sliding in) must fail the test, not
    // print a warning and leave a checkbox unticked that looks like an app bug.
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

  /// Lets sqlite finish: pumped fake time alone leaves later writes and
  /// stream re-reads in flight.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  /// [screen] behind a launcher route, so the screen's own `context.pop()`
  /// has somewhere to go.
  Future<void> pump(WidgetTester tester, Widget screen) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final router = GoRouter(
      initialLocation: '/screen',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(body: Text('launcher')),
          routes: [GoRoute(path: 'screen', builder: (_, _) => screen)],
        ),
      ],
    );
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        routerConfig: router,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ));
    await settle(tester);
  }

  // Fixture writes run on real async for the same reason as [settle].
  Future<T> run<T>(WidgetTester tester, Future<T> Function() body) async =>
      (await tester.runAsync(body)) as T;

  Future<String> songbook(WidgetTester tester, String name) => run(
      tester,
      () async => (await container
              .read(folderRepositoryProvider)
              .createFolder(name: name, userId: _userId, type: 'song'))
          .id);

  Future<String> song(WidgetTester tester, String title,
          {String? folderId, String? book}) =>
      run(
          tester,
          () async => (await container.read(songRepositoryProvider).createSong(
                userId: _userId,
                title: title,
                folderId: folderId,
                book: book,
              ))
              .id);

  Future<void> link(WidgetTester tester, String songId, List<String> ids) =>
      run(
          tester,
          () => container
              .read(songFolderRepositoryProvider)
              .setFoldersForSong(songId, ids, _userId));

  Future<List<String>> songbooksOf(WidgetTester tester, String songId) => run(
      tester,
      () async => (await container
              .read(songFolderRepositoryProvider)
              .watchSongbooksForSong(songId)
              .first)
          .map((b) => b.name)
          .toList());

  group('songs home', () {
    testWidgets('a songbook lists and counts songs linked into it',
        (tester) async {
      final hymns = await songbook(tester, 'Hymns');
      final ccm = await songbook(tester, 'CCM');
      await song(tester, 'Amazing Grace', folderId: hymns);
      final linked = await song(tester, 'Majesty', folderId: ccm);
      await song(tester, 'Only CCM', folderId: ccm);
      await link(tester, linked, [ccm, hymns]);

      await pump(tester, const SongsHomeScreen());
      await tester.tap(find.text('Songbooks'));
      await settle(tester);

      final hymnsRow = find.ancestor(
          of: find.text('Hymns'), matching: find.byType(InkWell)).first;
      expect(
          find.descendant(of: hymnsRow, matching: find.text('2 notes')),
          findsOneWidget,
          reason: 'the count must include the linked song');

      await tester.tap(find.text('Hymns'));
      await settle(tester);

      expect(find.text('Amazing Grace'), findsOneWidget);
      expect(find.text('Majesty'), findsOneWidget,
          reason: 'in Hymns by a link, not by folder_id');
      expect(find.text('Only CCM'), findsNothing);
    });

    testWidgets('moving a song takes it out of its other songbooks',
        (tester) async {
      final hymns = await songbook(tester, 'Hymns');
      final ccm = await songbook(tester, 'CCM');
      final target = await songbook(tester, 'Zion');
      final id = await song(tester, 'Majesty', folderId: hymns);
      await link(tester, id, [hymns, ccm]);

      await pump(tester, const SongsHomeScreen());
      await tester.longPress(find.text('Majesty'));
      await settle(tester);
      await tester.tap(find.byTooltip('Move'));
      await settle(tester);
      await tester.tap(find.descendant(
          of: find.byType(Dialog), matching: find.text('Zion')));
      await tester.pump();
      await tester.tap(find.descendant(
          of: find.byType(Dialog), matching: find.byType(FilledButton)));
      await settle(tester);

      expect(await songbooksOf(tester, id), ['Zion']);
      final row = await run(tester,
          () => container.read(songRepositoryProvider).getSongById(id));
      expect(row!.folderId, target);
    });
  });

  group('song detail', () {
    testWidgets('shows a chip per songbook and hides a book that repeats one',
        (tester) async {
      final hymns = await songbook(tester, 'Hymns');
      final ccm = await songbook(tester, 'CCM');
      final id = await song(tester, 'Majesty', folderId: hymns, book: 'hymns');
      await link(tester, id, [hymns, ccm]);

      await pump(tester, SongDetailScreen(songId: id));

      final chips = find.byIcon(Icons.menu_book);
      expect(chips, findsNWidgets(2));
      expect(find.text('Hymns'), findsOneWidget);
      expect(find.text('CCM'), findsOneWidget);
      expect(find.text('hymns'), findsNothing,
          reason: 'the free-text book names the same songbook');
    });
  });

  group('song editor', () {
    Future<void> openPicker(WidgetTester tester, String chipLabel) async {
      await tester.tap(find.text(chipLabel));
      // Past the sheet's entrance animation, or its rows are still below the
      // screen edge when tapped.
      await tester.pump(const Duration(milliseconds: 600));
      await settle(tester);
    }

    Future<void> toggle(WidgetTester tester, String name) async {
      await tester.tap(find.descendant(
          of: find.byType(CheckboxListTile), matching: find.text(name)));
      await tester.pump();
    }

    Future<void> doneAndSave(WidgetTester tester) async {
      await tester.tap(find.text('Done'));
      await settle(tester);
      await tester.tap(find.text('Save'));
      await settle(tester);
    }

    testWidgets('saving links the song to every songbook ticked',
        (tester) async {
      final hymns = await songbook(tester, 'Hymns');
      await songbook(tester, 'CCM');
      final id = await song(tester, 'Majesty', folderId: hymns);

      await pump(tester, AddSongScreen(songId: id));
      expect(find.text('Hymns'), findsOneWidget, reason: 'loaded primary');
      await openPicker(tester, 'Hymns');
      await toggle(tester, 'CCM');
      await doneAndSave(tester);

      expect(await songbooksOf(tester, id), ['Hymns', 'CCM']);
      expect(find.text('launcher'), findsOneWidget, reason: 'save completed');
    });

    testWidgets('unticking the primary makes the next songbook primary',
        (tester) async {
      final hymns = await songbook(tester, 'Hymns');
      final ccm = await songbook(tester, 'CCM');
      final id = await song(tester, 'Majesty', folderId: hymns);
      await link(tester, id, [hymns, ccm]);

      await pump(tester, AddSongScreen(songId: id));
      expect(find.text('Hymns +1'), findsOneWidget);
      await openPicker(tester, 'Hymns +1');
      await toggle(tester, 'Hymns');
      await doneAndSave(tester);

      expect(await songbooksOf(tester, id), ['CCM']);
      final row = await run(tester,
          () => container.read(songRepositoryProvider).getSongById(id));
      expect(row!.folderId, ccm);
    });

    testWidgets('a primary in Trash gives way to a live songbook on save',
        (tester) async {
      final trashed = await songbook(tester, 'Old');
      final ccm = await songbook(tester, 'CCM');
      final id = await song(tester, 'Majesty', folderId: trashed);
      await run(tester,
          () => container.read(folderRepositoryProvider).trashFolder(trashed));

      await pump(tester, AddSongScreen(songId: id));
      await openPicker(tester, 'Songbook');
      await toggle(tester, 'CCM');
      await doneAndSave(tester);

      final row = await run(tester,
          () => container.read(songRepositoryProvider).getSongById(id));
      expect(row!.folderId, ccm,
          reason: 'builds that read only folder_id must see the song in CCM');
      final linked = await run(tester,
          () => container.read(songFolderRepositoryProvider).getLinkedFolderIds(id));
      expect(linked, unorderedEquals([trashed, ccm]),
          reason: 'the trashed songbook keeps its link for a restore');
    });

    testWidgets('a save that fails part-way changes nothing', (tester) async {
      final hymns = await songbook(tester, 'Hymns');
      await songbook(tester, 'CCM');
      final id = await song(tester, 'Majesty', folderId: hymns);
      final opsBefore =
          await run(tester, () async => (await db.select(db.oplog).get()).length);

      await pump(tester, AddSongScreen(songId: id));
      await tester.enterText(find.byType(TextFormField).first, 'Renamed');
      await openPicker(tester, 'Hymns');
      await toggle(tester, 'CCM');
      await toggle(tester, 'Hymns');
      // The songbook step is the last write; make it fail after the song row
      // and its new primary have been written.
      await run(tester, () => db.customStatement('''
        CREATE TRIGGER fail_link_insert BEFORE INSERT ON sync_song_folders
        BEGIN SELECT RAISE(ABORT, 'boom'); END
      '''));
      await doneAndSave(tester);

      final row = await run(tester,
          () => container.read(songRepositoryProvider).getSongById(id));
      expect(row!.title, 'Majesty', reason: 'the song edit must roll back too');
      expect(row.folderId, hymns, reason: 'and so must the new primary');
      expect(
          await run(tester, () async => (await db.select(db.oplog).get()).length),
          opsBefore,
          reason: 'no half of the save may be queued to sync');
      expect(find.text('launcher'), findsNothing,
          reason: 'the editor stays open so the user can retry');
    });

    testWidgets('a new song is saved into the songbooks ticked', (tester) async {
      await songbook(tester, 'Hymns');
      await songbook(tester, 'CCM');

      await pump(tester, const AddSongScreen());
      await tester.enterText(
          find.byType(TextFormField).first, 'Brand New');
      await openPicker(tester, 'Songbook');
      await toggle(tester, 'CCM');
      await toggle(tester, 'Hymns');
      await doneAndSave(tester);

      final songs = await run(tester, () => db.select(db.songs).get());
      expect(songs, hasLength(1));
      expect(await songbooksOf(tester, songs.single.id), ['CCM', 'Hymns'],
          reason: 'first ticked is primary, then the rest by name');
    });
  });
}
