// The reader as a page of text: verses run on in one paragraph, tapping selects
// them, and the panel that appears acts on the whole selection.

import 'dart:convert';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:notify/core/database/sync_database.dart';
import 'package:notify/core/sync/providers/sync_providers.dart';
import 'package:notify/core/theme/app_theme.dart';
import 'package:notify/features/bible/data/bible_repository.dart';
import 'package:notify/features/bible/domain/models/bible_book_entity.dart';
import 'package:notify/features/bible/domain/models/bible_highlight_entity.dart';
import 'package:notify/features/bible/domain/models/bible_verse_entity.dart';
import 'package:notify/features/bible/presentation/providers/bible_chapter_providers.dart';
import 'package:notify/features/bible/presentation/providers/bible_providers.dart';
import 'package:notify/features/bible/presentation/providers/verse_tag_providers.dart';
import 'package:notify/features/bible/presentation/screens/bible_chapter_screen.dart';
import 'package:notify/features/bible/presentation/widgets/chapter_verse_list.dart';
import 'package:notify/features/bible/presentation/widgets/flowing_chapter_text.dart';
import 'package:notify/features/bible/presentation/widgets/verse_selection_panel.dart';
import 'package:notify/l10n/app_localizations.dart';

class _FakeRepo implements BibleRepository {
  @override
  BibleBookEntity? getBookById(int bookId) => const BibleBookEntity(
        id: 1,
        name: 'Genesis',
        shortName: 'Gen',
        testament: 1,
        sortOrder: 1,
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

List<BibleVerseEntity> _verses(String version, [int count = 8]) => [
      for (var n = 1; n <= count; n++)
        BibleVerseEntity(
          id: n,
          translation: version,
          bookId: 1,
          chapter: 1,
          verse: n,
          text: 'Words of verse $n.',
        ),
    ];

/// The paragraph that holds the verses (the chapter title and verse numbers are
/// separate pieces of text).
Finder _paragraph() => find.byWidgetPredicate(
    (w) => w is RichText && w.text.toPlainText().contains('Words of verse 1.'));

void main() {
  late SyncDatabase db;
  late ProviderContainer container;
  late SharedPreferences prefs;

  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  Future<void> build({int verseCount = 8}) async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    db = SyncDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      syncDatabaseProvider.overrideWithValue(db),
      currentUserIdProvider.overrideWith((ref) => 'user-1'),
      deviceIdProvider.overrideWith((ref) => 'device-1'),
      bibleRepositoryProvider.overrideWithValue(_FakeRepo()),
      bibleTranslationsProvider.overrideWithValue(['KJV', 'NIV']),
      bibleVersesProvider
          .overrideWith((ref, p) => _verses(p.translation, verseCount)),
      bibleChaptersProvider.overrideWith((ref, p) => [1, 2, 3]),
      bibleBooksProvider.overrideWithValue([]),
      chapterVerseTagsProvider.overrideWith((ref, p) => <int, Set<String>>{}),
    ]);
  }

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump(const Duration(milliseconds: 100));
  }

  Future<void> pump(
    WidgetTester tester, {
    int? scrollToVerse,
    Size size = const Size(402, 874),
    ThemeData? theme,
  }) async {
    tester.view.physicalSize = size * 3;
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: theme ?? AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: BibleChapterScreen(
          bookId: 1,
          chapter: 1,
          initialTranslation: 'KJV',
          scrollToVerse: scrollToVerse,
        ),
      ),
    ));
    await settle(tester);
  }

  /// Taps verse [n] on its own words (the middle of the paragraph's box can
  /// fall in the blank end of its last line).
  Future<void> tapVerse(WidgetTester tester, int n) async {
    final render = tester.renderObject<RenderParagraph>(_paragraph());
    final text = render.text.toPlainText();
    final at = text.indexOf('Words of verse $n.');
    final boxes = render.getBoxesForSelection(
        TextSelection(baseOffset: at + 2, extentOffset: at + 8));
    final local = boxes.first.toRect().center;
    await tester.tapAt(render.localToGlobal(local));
    await settle(tester);
  }

  Iterable<TextSpan> spans(WidgetTester tester) sync* {
    final rich = tester.widget<RichText>(_paragraph());
    Iterable<TextSpan> walk(InlineSpan s) sync* {
      if (s is TextSpan) {
        yield s;
        for (final c in s.children ?? const <InlineSpan>[]) {
          yield* walk(c);
        }
      }
    }

    yield* walk(rich.text);
  }

  TextSpan verseSpan(WidgetTester tester, int n) =>
      spans(tester).firstWhere((s) => s.text == 'Words of verse $n. ');

  testWidgets('the chapter is set as one page of text under a large title',
      (tester) async {
    await build();
    await pump(tester);

    expect(find.byType(FlowingChapterText), findsOneWidget);
    expect(find.byType(ChapterVerseList), findsNothing);
    expect(find.text('Genesis 1'), findsOneWidget, reason: 'the chapter title');
    // All eight verses are inside the same paragraph.
    final text = tester
        .renderObject<RenderParagraph>(_paragraph())
        .text
        .toPlainText();
    for (var n = 1; n <= 8; n++) {
      expect(text, contains('Words of verse $n.'));
    }
  });

  testWidgets('tapping a verse selects it, and the panel names it',
      (tester) async {
    await build();
    await pump(tester);
    expect(find.byType(VerseSelectionPanel), findsNothing);

    await tapVerse(tester, 3);

    expect(find.byType(VerseSelectionPanel), findsOneWidget);
    expect(find.text('Genesis 1:3'), findsOneWidget);
    expect(find.text('1 verse selected'), findsOneWidget);
    expect(verseSpan(tester, 3).style?.decoration, TextDecoration.underline);
    expect(verseSpan(tester, 4).style?.decoration, isNull);
  });

  testWidgets('tapping a selected verse again unselects it', (tester) async {
    await build();
    await pump(tester);
    await tapVerse(tester, 3);
    await tapVerse(tester, 3);

    expect(find.byType(VerseSelectionPanel), findsNothing);
  });

  testWidgets('verses add up to a selection, written as ranges',
      (tester) async {
    await build();
    await pump(tester);
    await tapVerse(tester, 3);
    await tapVerse(tester, 4);
    await tapVerse(tester, 5);
    await tapVerse(tester, 7);

    expect(find.text('Genesis 1:3–5, 7'), findsOneWidget);
    expect(find.text('4 verses selected'), findsOneWidget);
    expect(find.text('Select neighbouring verses to add a note'),
        findsOneWidget,
        reason: '7 is not next to 3-5, so a note is not possible');
  });

  testWidgets('the close button clears the selection', (tester) async {
    await build();
    await pump(tester);
    await tapVerse(tester, 2);
    await tester.tap(find.byTooltip('Clear selection'));
    await settle(tester);

    expect(find.byType(VerseSelectionPanel), findsNothing);
  });

  testWidgets('back clears the selection before it leaves the chapter',
      (tester) async {
    await build();
    await pump(tester);
    await tapVerse(tester, 2);

    await tester.binding.handlePopRoute();
    await settle(tester);

    expect(find.byType(VerseSelectionPanel), findsNothing);
    expect(find.byType(BibleChapterScreen), findsOneWidget);
  });

  testWidgets('one tap on a colour highlights every selected verse as one',
      (tester) async {
    await build();
    await pump(tester);
    await tapVerse(tester, 2);
    await tapVerse(tester, 3);
    await tapVerse(tester, 4);

    await tester.tap(find.bySemanticsLabel('Pink highlight'));
    await settle(tester);
    await settle(tester);

    final rows = await tester.runAsync(() => db.select(db.bibleHighlights).get());
    expect(rows!.length, 1);
    expect([rows.single.verseStart, rows.single.verseEnd], [2, 4]);
    expect(rows.single.color, HighlightColor.pink.name);

    expect(verseSpan(tester, 3).style?.backgroundColor,
        HighlightColor.pink.backgroundColor);
    expect(verseSpan(tester, 5).style?.backgroundColor, isNull);
    expect(find.byType(VerseSelectionPanel), findsOneWidget,
        reason: 'the panel stays, so the colour can be changed');
  });

  testWidgets('recolouring part of a highlight leaves the rest as it was',
      (tester) async {
    await build();
    await pump(tester);
    for (final n in [2, 3, 4, 5]) {
      await tapVerse(tester, n);
    }
    await tester.tap(find.bySemanticsLabel('Yellow highlight'));
    await settle(tester);
    await settle(tester);

    // Now only 3 and 4 stay selected.
    await tapVerse(tester, 2);
    await tapVerse(tester, 5);
    await tester.tap(find.bySemanticsLabel('Blue highlight'));
    await settle(tester);
    await settle(tester);

    Color? bg(int n) => verseSpan(tester, n).style?.backgroundColor;
    expect(bg(2), HighlightColor.yellow.backgroundColor);
    expect(bg(3), HighlightColor.blue.backgroundColor);
    expect(bg(4), HighlightColor.blue.backgroundColor);
    expect(bg(5), HighlightColor.yellow.backgroundColor);
  });

  testWidgets('Remove highlight clears the colour from the selection only',
      (tester) async {
    await build();
    await pump(tester);
    for (final n in [2, 3, 4]) {
      await tapVerse(tester, n);
    }
    await tester.tap(find.bySemanticsLabel('Green highlight'));
    await settle(tester);
    await settle(tester);

    // 2 and 4 are selected, 3 is not: leave 3 out by tapping it off.
    await tapVerse(tester, 3);
    await tester.tap(find.text('Remove highlight'));
    await settle(tester);
    await settle(tester);

    // 2 and 4 are only selected now (a faint tint); 3 keeps its colour.
    expect(verseSpan(tester, 2).style?.backgroundColor,
        isNot(HighlightColor.green.backgroundColor));
    expect(verseSpan(tester, 3).style?.backgroundColor,
        HighlightColor.green.backgroundColor);
    expect(verseSpan(tester, 4).style?.backgroundColor,
        isNot(HighlightColor.green.backgroundColor));
  });

  testWidgets('a note on several verses marks them and is labelled for a group',
      (tester) async {
    await build();
    await pump(tester);
    for (final n in [3, 4, 5]) {
      await tapVerse(tester, n);
    }
    await tester.tap(find.text('Add note'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'for the three');
    await tester.pump();
    await tester.tap(find.widgetWithText(TextButton, 'Save note'));
    await settle(tester);
    await settle(tester);

    final rows = await tester.runAsync(() => db.select(db.bibleVerseNotes).get());
    expect([rows!.single.verseStart, rows.single.verseEnd], [3, 5]);
    expect(find.text('Verses 3–5'), findsOneWidget);

    // Selecting just one of the three shows the same group note.
    await tester.tap(find.byTooltip('Clear selection'));
    await settle(tester);
    await tapVerse(tester, 4);
    expect(find.text('for the three'), findsOneWidget);
    expect(find.text('Verses 3–5'), findsOneWidget);

    // And each of the three carries the marker.
    expect(find.byIcon(Icons.sticky_note_2_outlined), findsNWidgets(3 + 0));
  });

  testWidgets('verse numbers can be switched off in the reading settings',
      (tester) async {
    await build();
    await pump(tester);
    expect(find.descendant(
        of: find.byType(FlowingChapterText), matching: find.text('3')),
        findsOneWidget);

    await tester.tap(find.byTooltip('Reading settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show verse numbers'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(10, 10)); // the barrier
    await tester.pumpAndSettle();

    expect(find.descendant(
        of: find.byType(FlowingChapterText), matching: find.text('3')),
        findsNothing);
    expect(prefs.getBool('bible_reader_show_verse_numbers'), isFalse);
  });

  testWidgets('the typeface can be changed and is remembered', (tester) async {
    await build();
    await pump(tester);
    String? family() => tester
        .widget<RichText>(_paragraph())
        .text
        .style
        ?.fontFamily;
    expect(family(), 'Georgia');

    await tester.tap(find.byTooltip('Reading settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sans'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(family(), isNot('Georgia'));
    expect(prefs.getString('bible_reader_typeface'), 'sans');
  });

  testWidgets('opening at a verse scrolls to it', (tester) async {
    await build(verseCount: 80);
    await pump(tester, scrollToVerse: 60);
    await settle(tester);
    await tester.pump(const Duration(milliseconds: 500));

    final scrollable = tester.state<ScrollableState>(find.descendant(
        of: find.byType(FlowingChapterText),
        matching: find.byType(Scrollable)));
    expect(scrollable.position.pixels, greaterThan(300));
    await tester.pump(const Duration(seconds: 3)); // the flash fades out
  });

  testWidgets('lays out on a narrow phone at 200% text', (tester) async {
    await build();
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pump(tester, size: const Size(320, 640));
    await tapVerse(tester, 1);

    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'on a highlighted verse in the dark theme the number and the note marker '
      'stay readable, because they sit off the pastel', (tester) async {
    await build();
    await tester.runAsync(() async {
      await container.read(bibleHighlightRepositoryProvider).createHighlight(
          bookId: 1,
          chapter: 1,
          verseStart: 3,
          verseEnd: 3,
          color: HighlightColor.yellow);
      await container
          .read(bibleVerseNoteRepositoryProvider)
          .addNote(bookId: 1, chapter: 1, verse: 3, content: 'n');
    });
    final dark = AppTheme.dark();
    await pump(tester, theme: dark);

    final number = tester.widget<Text>(find.descendant(
        of: find.byType(FlowingChapterText), matching: find.text('3')));
    expect(number.style?.color, AppTheme.bibleGreen,
        reason: 'not the dark highlight ink, which vanishes on a dark page');
    final marker = tester.widget<Icon>(find.descendant(
        of: find.byType(FlowingChapterText),
        matching: find.byIcon(Icons.sticky_note_2_outlined)));
    expect(marker.color, dark.colorScheme.onSurfaceVariant);
    expect(marker.color, isNot(AppTheme.onHighlight));
    // The words themselves are on the pastel, so they are dark.
    expect(verseSpan(tester, 3).style?.color, AppTheme.onHighlight);
  });

  testWidgets('an unsaved note is dropped when the selection changes',
      (tester) async {
    await build();
    await pump(tester);
    await tapVerse(tester, 4);
    await tapVerse(tester, 5);
    await tester.tap(find.text('Add note'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'meant for 4 and 5');
    await tester.pump();

    await tapVerse(tester, 6);

    expect(find.byType(TextField), findsNothing,
        reason: 'the note was started on 4-5, not 4-6');
    final rows = await tester.runAsync(() => db.select(db.bibleVerseNotes).get());
    expect(rows, isEmpty);
  });

  testWidgets('two colours tapped in quick succession end as one highlight',
      (tester) async {
    await build();
    await pump(tester);
    await tapVerse(tester, 2);
    await tester.tap(find.bySemanticsLabel('Green highlight'));
    await settle(tester);
    await settle(tester);

    // Both taps land before the first write has come back.
    await tester.tap(find.bySemanticsLabel('Blue highlight'));
    await tester.tap(find.bySemanticsLabel('Pink highlight'));
    await settle(tester);
    await settle(tester);
    await settle(tester);

    final rows = await tester.runAsync(() => db.select(db.bibleHighlights).get());
    expect(rows!.where((r) => r.deleted == 0).length, 1,
        reason: 'no overlapping duplicates');
    expect(rows.where((r) => r.deleted == 0).single.color,
        HighlightColor.pink.name);
    final ops = await tester.runAsync(() => db.select(db.oplog).get());
    final versions = [
      for (final o in ops!.where((o) => o.entityType == 'bibleHighlight'))
        (jsonDecode(o.payloadJson) as Map)['version'],
    ];
    expect(versions.toSet().length, versions.length,
        reason: 'each write is its own version, so none bounces on the server');
  });

  testWidgets('moving to another chapter does not scroll to the opening verse '
      'again', (tester) async {
    await build(verseCount: 80);
    await pump(tester, scrollToVerse: 60);
    await tester.pump(const Duration(seconds: 3));

    await tester.tap(find.byIcon(Icons.chevron_right));
    await settle(tester);
    await tester.pump(const Duration(seconds: 3));

    final scrollable = tester.state<ScrollableState>(find.descendant(
        of: find.byType(FlowingChapterText),
        matching: find.byType(Scrollable)));
    expect(scrollable.position.pixels, 0);
  });
}
