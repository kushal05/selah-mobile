// A verse that has a note written on it is marked in the chapter list, whether
// the note came from the verse sheet or from a highlight; verses without one
// are not.

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:notify/core/database/sync_database.dart';
import 'package:notify/core/sync/providers/sync_providers.dart';
import 'package:notify/core/theme/app_theme.dart';
import 'package:notify/features/bible/domain/models/bible_highlight_entity.dart';
import 'package:notify/features/bible/domain/models/bible_verse_entity.dart';
import 'package:notify/features/bible/presentation/providers/bible_chapter_providers.dart';
import 'package:notify/features/bible/presentation/widgets/chapter_verse_list.dart';
import 'package:notify/l10n/app_localizations.dart';

BibleVerseEntity _v(int n) => BibleVerseEntity(
      id: n,
      translation: 'KJV',
      bookId: 43,
      chapter: 3,
      verse: n,
      text: 'Verse number $n text',
    );

void main() {
  late SyncDatabase db;
  late ProviderContainer container;

  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    db = SyncDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      syncDatabaseProvider.overrideWithValue(db),
      currentUserIdProvider.overrideWith((ref) => 'user-1'),
      deviceIdProvider.overrideWith((ref) => 'device-1'),
    ]);
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 150)));
    await tester.pump(const Duration(milliseconds: 50));
  }

  Future<void> pumpList(WidgetTester tester,
      {List<BibleHighlightEntity> highlights = const [],
      ThemeData? theme}) async {
    tester.view.physicalSize = const Size(402, 874) * 3;
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: theme ?? AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ChapterVerseList(
            verses: [_v(15), _v(16), _v(17)],
            highlights: highlights,
            scrollController: ScrollController(),
          ),
        ),
      ),
    ));
    await settle(tester);
  }

  Finder markerFor(int verse) => find.descendant(
        of: find.ancestor(
            of: find.text('Verse number $verse text'),
            matching: find.byType(Row)),
        matching: find.byIcon(Icons.sticky_note_2_outlined),
      );

  testWidgets('no notes, no markers', (tester) async {
    await pumpList(tester);
    expect(find.byIcon(Icons.sticky_note_2_outlined), findsNothing);
  });

  testWidgets('a verse with a note is marked, its neighbours are not',
      (tester) async {
    await tester.runAsync(() => container
        .read(bibleVerseNoteRepositoryProvider)
        .addNote(bookId: 43, chapter: 3, verse: 16, content: 'a thought'));
    await pumpList(tester);

    expect(find.byIcon(Icons.sticky_note_2_outlined), findsOneWidget);
    expect(markerFor(16), findsOneWidget);
    expect(markerFor(15), findsNothing);
    expect(markerFor(17), findsNothing);
  });

  testWidgets('the marker follows a new note and a deleted one',
      (tester) async {
    await pumpList(tester);
    expect(find.byIcon(Icons.sticky_note_2_outlined), findsNothing);

    final note = await tester.runAsync(() => container
        .read(bibleVerseNoteRepositoryProvider)
        .addNote(bookId: 43, chapter: 3, verse: 17, content: 'new'));
    await settle(tester);
    await settle(tester);
    expect(markerFor(17), findsOneWidget);

    await tester.runAsync(() =>
        container.read(bibleVerseNoteRepositoryProvider).deleteNote(note!));
    await settle(tester);
    await settle(tester);
    expect(find.byIcon(Icons.sticky_note_2_outlined), findsNothing);
  });

  testWidgets('a note on another chapter does not mark this one',
      (tester) async {
    await tester.runAsync(() => container
        .read(bibleVerseNoteRepositoryProvider)
        .addNote(bookId: 43, chapter: 4, verse: 16, content: 'elsewhere'));
    await pumpList(tester);
    expect(find.byIcon(Icons.sticky_note_2_outlined), findsNothing);
  });

  testWidgets('on a plain verse the marker is readable in the dark theme',
      (tester) async {
    await tester.runAsync(() => container
        .read(bibleVerseNoteRepositoryProvider)
        .addNote(bookId: 43, chapter: 3, verse: 16, content: 'a thought'));
    await pumpList(tester, theme: AppTheme.dark());

    final icon = tester.widget<Icon>(find.byIcon(Icons.sticky_note_2_outlined));
    expect(icon.color, isNot(AppTheme.onHighlight),
        reason: 'the dark ink belongs on a highlight pastel, not the dark page');
    expect(icon.color, AppTheme.dark().colorScheme.onSurfaceVariant);
  });

  testWidgets('on a highlighted verse the marker keeps the dark ink',
      (tester) async {
    await tester.runAsync(() => container
        .read(bibleVerseNoteRepositoryProvider)
        .addNote(bookId: 43, chapter: 3, verse: 16, content: 'a thought'));
    final now = DateTime.now().millisecondsSinceEpoch;
    await pumpList(tester, theme: AppTheme.dark(), highlights: [
      BibleHighlightEntity(
        id: 'h',
        bookId: 43,
        chapter: 3,
        verseStart: 16,
        verseEnd: 16,
        color: HighlightColor.yellow,
        createdAt: now,
        updatedAt: now,
      ),
    ]);

    final icon = tester.widget<Icon>(find.byIcon(Icons.sticky_note_2_outlined));
    expect(icon.color, AppTheme.onHighlight);
  });
}
