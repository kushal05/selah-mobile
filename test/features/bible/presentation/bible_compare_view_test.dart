// The compare view lays a verse's versions one after another instead of in
// side-by-side columns: pick the versions in a bar along the top, and each verse
// shows them stacked, in the order picked.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:notify/core/sync/models/tag_model.dart';
import 'package:notify/core/sync/providers/sync_providers.dart';
import 'package:notify/core/theme/app_theme.dart';
import 'package:notify/features/bible/data/bible_repository.dart';
import 'package:notify/features/bible/domain/models/bible_book_entity.dart';
import 'package:notify/features/bible/domain/models/bible_verse_entity.dart';
import 'package:notify/features/bible/presentation/providers/bible_chapter_providers.dart';
import 'package:notify/features/bible/presentation/providers/bible_providers.dart';
import 'package:notify/features/bible/presentation/providers/verse_tag_providers.dart';
import 'package:notify/features/bible/presentation/screens/bible_chapter_screen.dart';
import 'package:notify/l10n/app_localizations.dart';
import 'package:notify/shared/widgets/selectable_chip.dart';

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

BibleVerseEntity _v(String version, int n, String text) => BibleVerseEntity(
      id: n,
      translation: version,
      bookId: 1,
      chapter: 1,
      verse: n,
      text: text,
    );

/// NIV is missing verse 2, to show a gap.
List<BibleVerseEntity> _versesFor(String version) => switch (version) {
      'KJV' => [_v('KJV', 1, 'In the beginning (KJV)'), _v('KJV', 2, 'And the earth (KJV)')],
      'NIV' => [_v('NIV', 1, 'In the beginning (NIV)')],
      'ESV' => [_v('ESV', 1, 'In the beginning (ESV)'), _v('ESV', 2, 'The earth was (ESV)')],
      _ => const [],
    };

Future<void> _pump(
  WidgetTester tester, {
  List<String> translations = const ['KJV', 'NIV', 'ESV'],
  ThemeData? theme,
  Size size = const Size(402, 874),
  double textScale = 1.0,
  Map<int, Set<String>> verseTags = const {},
  List<TagModel> tags = const [],
}) async {
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();

  await tester.pumpWidget(ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      bibleRepositoryProvider.overrideWithValue(_FakeRepo()),
      bibleTranslationsProvider.overrideWithValue(translations),
      bibleVersesProvider.overrideWith((ref, p) => _versesFor(p.translation)),
      bibleChaptersProvider.overrideWith((ref, p) => [1, 2, 3]),
      bibleBooksProvider.overrideWithValue([]),
      chapterHighlightsProvider.overrideWith((ref, p) => Stream.value([])),
      chapterVerseTagsProvider.overrideWith((ref, p) => verseTags),
      tagsStreamProvider.overrideWith((ref) => Stream.value(tags)),
      chapterNotedVersesProvider
          .overrideWith((ref, p) => Stream.value(<int>{})),
    ],
    child: MaterialApp(
      theme: theme ?? AppTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: const BibleChapterScreen(
          bookId: 1, chapter: 1, initialTranslation: 'KJV'),
    ),
  ));
  await tester.pump(const Duration(milliseconds: 200));
}

Future<void> _menu(WidgetTester tester, String item) async {
  await tester.tap(find.byTooltip('More options'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(item));
  await tester.pumpAndSettle();
}

double _top(WidgetTester tester, String text) =>
    tester.getTopLeft(find.text(text)).dy;

Finder _chip(String code) => find.descendant(
    of: find.byType(SelectableChip), matching: find.text(code));

void main() {
  testWidgets('single version is the default: no bar, one text per verse',
      (tester) async {
    await _pump(tester);

    expect(find.byType(SelectableChip), findsNothing);
    expect(find.text('In the beginning (KJV)'), findsOneWidget);
    expect(find.text('In the beginning (NIV)'), findsNothing);
  });

  testWidgets('Compare versions shows a bar to pick from, KJV and NIV chosen',
      (tester) async {
    await _pump(tester);
    await _menu(tester, 'Compare versions');

    for (final code in ['KJV', 'NIV', 'ESV']) {
      expect(_chip(code), findsOneWidget);
    }
    final chips = tester
        .widgetList<SelectableChip>(find.byType(SelectableChip))
        .toList();
    expect(chips.where((c) => c.isSelected).map((c) => c.label),
        ['KJV', 'NIV']);
  });

  testWidgets('each verse shows its versions one after another, not side by side',
      (tester) async {
    await _pump(tester);
    await _menu(tester, 'Compare versions');

    final kjv = tester.getTopLeft(find.text('In the beginning (KJV)'));
    final niv = tester.getTopLeft(find.text('In the beginning (NIV)'));

    expect(niv.dy, greaterThan(kjv.dy), reason: 'NIV sits under KJV');
    expect(niv.dx, kjv.dx, reason: 'same column, not beside it');
    // Verse 1's versions come before verse 2.
    expect(_top(tester, 'And the earth (KJV)'), greaterThan(niv.dy));
  });

  testWidgets('the version of each text is named above it', (tester) async {
    await _pump(tester);
    await _menu(tester, 'Compare versions');

    // One label per version per verse (the bar's chips say KJV/NIV too).
    final labels = find.byWidgetPredicate(
        (w) => w is Text && w.data == 'KJV' && w.style?.fontSize == 11);
    expect(labels, findsNWidgets(2), reason: 'verses 1 and 2');
  });

  testWidgets('a version that lacks a verse says so', (tester) async {
    await _pump(tester);
    await _menu(tester, 'Compare versions');

    expect(find.text('Not available in this version'), findsOneWidget,
        reason: 'NIV has no verse 2');
  });

  testWidgets('adding a version puts it after the others', (tester) async {
    await _pump(tester);
    await _menu(tester, 'Compare versions');

    await tester.tap(_chip('ESV'));
    await tester.pumpAndSettle();

    expect(_top(tester, 'In the beginning (KJV)'),
        lessThan(_top(tester, 'In the beginning (NIV)')));
    expect(_top(tester, 'In the beginning (NIV)'),
        lessThan(_top(tester, 'In the beginning (ESV)')));
  });

  testWidgets('versions are shown in the order they were picked',
      (tester) async {
    await _pump(tester);
    await _menu(tester, 'Compare versions');

    // Take KJV out and put it back: it is now last.
    await tester.tap(_chip('KJV'));
    await tester.pumpAndSettle();
    await tester.tap(_chip('KJV'));
    await tester.pumpAndSettle();

    expect(_top(tester, 'In the beginning (NIV)'),
        lessThan(_top(tester, 'In the beginning (KJV)')));
  });

  testWidgets('taking a version out removes it, but one always stays',
      (tester) async {
    await _pump(tester);
    await _menu(tester, 'Compare versions');

    await tester.tap(_chip('NIV'));
    await tester.pumpAndSettle();
    expect(find.text('In the beginning (NIV)'), findsNothing);
    expect(find.text('In the beginning (KJV)'), findsOneWidget);

    // KJV is the last one: tapping it changes nothing.
    await tester.tap(_chip('KJV'));
    await tester.pumpAndSettle();
    expect(find.text('In the beginning (KJV)'), findsOneWidget);
  });

  testWidgets('the version pill gives way to the bar while comparing',
      (tester) async {
    await _pump(tester);
    expect(
        find.descendant(of: find.byType(AppBar), matching: find.text('KJV')),
        findsOneWidget);

    await _menu(tester, 'Compare versions');

    expect(
        find.descendant(of: find.byType(AppBar), matching: find.text('KJV')),
        findsNothing);
  });

  testWidgets('Single version goes back to one text per verse', (tester) async {
    await _pump(tester);
    await _menu(tester, 'Compare versions');
    await _menu(tester, 'Single version');

    expect(find.byType(SelectableChip), findsNothing);
    expect(find.text('In the beginning (NIV)'), findsNothing);
    expect(find.text('In the beginning (KJV)'), findsOneWidget);
    expect(
        find.descendant(of: find.byType(AppBar), matching: find.text('KJV')),
        findsOneWidget);
  });

  testWidgets('with only one version installed, there is nothing to compare',
      (tester) async {
    await _pump(tester, translations: const ['KJV']);

    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();

    final item = tester.widget<PopupMenuItem<String>>(
        find.widgetWithText(PopupMenuItem<String>, 'Compare versions'));
    expect(item.enabled, isFalse);
  });

  for (final entry in {
    'light': AppTheme.light(),
    'dark': AppTheme.dark(),
  }.entries) {
    testWidgets(
        'lays out on a narrow phone at 200% text in the ${entry.key} theme',
        (tester) async {
      await _pump(tester,
          theme: entry.value, size: const Size(320, 640), textScale: 2.0);
      await _menu(tester, 'Compare versions');
      await tester.tap(_chip('ESV'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      // Verse 1 in all three versions (verse 2 is below the fold at this size).
      for (final v in ['KJV', 'NIV', 'ESV']) {
        expect(find.text('In the beginning ($v)'), findsOneWidget);
      }
    });
  }

  testWidgets('a verse\'s tags show once, not once per version', (tester) async {
    await _pump(
      tester,
      verseTags: {
        1: {'t1'}
      },
      tags: [TagModel.create(id: 't1', userId: 'u', name: 'faith')],
    );
    await _menu(tester, 'Compare versions');
    await tester.tap(_chip('ESV'));
    await tester.pumpAndSettle();

    expect(find.text('faith'), findsOneWidget,
        reason: 'three versions of verse 1, one set of tags');
  });
}
