// Reader page colours: each keeps its text readable, the choice applies to the
// page and is remembered, and Auto follows the app.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:notify/core/sync/providers/sync_providers.dart';
import 'package:notify/core/theme/app_theme.dart';
import 'package:notify/features/bible/data/bible_repository.dart';
import 'package:notify/features/bible/domain/models/bible_book_entity.dart';
import 'package:notify/features/bible/domain/models/bible_verse_entity.dart';
import 'package:notify/features/bible/presentation/providers/bible_chapter_providers.dart';
import 'package:notify/features/bible/presentation/providers/bible_providers.dart';
import 'package:notify/features/bible/presentation/providers/bible_reader_preferences.dart';
import 'package:notify/features/bible/presentation/providers/verse_tag_providers.dart';
import 'package:notify/features/bible/presentation/screens/bible_chapter_screen.dart';
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

double _ratio(Color a, Color b) {
  final l1 = a.computeLuminance(), l2 = b.computeLuminance();
  final hi = l1 > l2 ? l1 : l2, lo = l1 > l2 ? l2 : l1;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  group('every theme is readable', () {
    for (final t in ReaderTheme.values.where((t) => t != ReaderTheme.auto)) {
      test('${t.name}: text, secondary text and the accent are 4.5:1+', () {
        expect(_ratio(t.text!, t.background!), greaterThanOrEqualTo(4.5));
        expect(_ratio(t.muted!, t.background!), greaterThanOrEqualTo(4.5));
        expect(_ratio(t.accent!, t.background!), greaterThanOrEqualTo(4.5),
            reason: 'verse numbers sit on the page');
        // Text on a pill or field.
        expect(_ratio(t.text!, t.chip!), greaterThanOrEqualTo(4.5));
        expect(_ratio(t.muted!, t.raised!), greaterThanOrEqualTo(4.5),
            reason: 'the selection panel is on the raised ground');
        expect(_ratio(t.accent!, t.raised!), greaterThanOrEqualTo(4.5));
      });
    }
  });

  test('Auto leaves the app theme as it is', () {
    final app = AppTheme.dark();
    expect(identical(ReaderTheme.auto.apply(app), app), isTrue);
  });

  test('a theme sets the page and text colours and the brightness', () {
    final themed = ReaderTheme.sepia.apply(AppTheme.dark());
    expect(themed.scaffoldBackgroundColor, ReaderTheme.sepia.background);
    expect(themed.colorScheme.onSurface, ReaderTheme.sepia.text);
    expect(themed.brightness, Brightness.light,
        reason: 'sepia is a light page even in a dark app');
    expect(ReaderTheme.night.apply(AppTheme.light()).brightness,
        Brightness.dark);
  });

  group('on the screen', () {
    late SharedPreferences prefs;

    Future<void> pump(WidgetTester tester, {ThemeData? app}) async {
      tester.view.physicalSize = const Size(402, 874) * 3;
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          bibleRepositoryProvider.overrideWithValue(_FakeRepo()),
          bibleTranslationsProvider.overrideWithValue(['KJV']),
          bibleVersesProvider.overrideWith((ref, p) => const [
                BibleVerseEntity(
                    id: 1,
                    translation: 'KJV',
                    bookId: 1,
                    chapter: 1,
                    verse: 1,
                    text: 'In the beginning'),
              ]),
          bibleChaptersProvider.overrideWith((ref, p) => [1, 2]),
          bibleBooksProvider.overrideWithValue([]),
          chapterHighlightsProvider.overrideWith((ref, p) => Stream.value([])),
          chapterNotedVersesProvider
              .overrideWith((ref, p) => Stream.value(<int>{})),
          chapterVerseTagsProvider
              .overrideWith((ref, p) => <int, Set<String>>{}),
        ],
        child: MaterialApp(
          theme: app ?? AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const BibleChapterScreen(
              bookId: 1, chapter: 1, initialTranslation: 'KJV'),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 200));
    }

    Color pageColor(WidgetTester tester) =>
        tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor ??
        Theme.of(tester.element(find.byType(Scaffold))).scaffoldBackgroundColor;

    Future<void> choose(WidgetTester tester, String name) async {
      await tester.tap(find.byTooltip('Reading settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel(name));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
    }

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
    });

    testWidgets('choosing Sepia colours the page and is remembered',
        (tester) async {
      await pump(tester);
      await choose(tester, 'Sepia');

      expect(pageColor(tester), ReaderTheme.sepia.background);
      expect(prefs.getString('bible_reader_theme'), 'sepia');
    });

    testWidgets('a remembered theme is used when the reader opens',
        (tester) async {
      SharedPreferences.setMockInitialValues({'bible_reader_theme': 'night'});
      prefs = await SharedPreferences.getInstance();
      await pump(tester);

      expect(pageColor(tester), ReaderTheme.night.background);
    });

    testWidgets('an unknown remembered theme falls back to Auto',
        (tester) async {
      SharedPreferences.setMockInitialValues({'bible_reader_theme': 'neon'});
      prefs = await SharedPreferences.getInstance();
      await pump(tester);

      expect(pageColor(tester), AppTheme.light().scaffoldBackgroundColor);
    });

    testWidgets('Auto follows the app theme', (tester) async {
      await pump(tester, app: AppTheme.dark());
      expect(pageColor(tester), AppTheme.dark().scaffoldBackgroundColor);

      await choose(tester, 'Light');
      expect(pageColor(tester), ReaderTheme.light.background);

      await choose(tester, 'Auto');
      expect(pageColor(tester), AppTheme.dark().scaffoldBackgroundColor);
    });

    testWidgets('the settings sheet is in the chosen colours too',
        (tester) async {
      SharedPreferences.setMockInitialValues({'bible_reader_theme': 'slate'});
      prefs = await SharedPreferences.getInstance();
      await pump(tester);
      await tester.tap(find.byTooltip('Reading settings'));
      await tester.pumpAndSettle();

      final sheetColor = tester
          .widget<Material>(find
              .ancestor(
                  of: find.text('Reading settings'),
                  matching: find.byType(Material))
              .first)
          .color;
      expect(sheetColor, ReaderTheme.slate.raised);
    });
  });
}
