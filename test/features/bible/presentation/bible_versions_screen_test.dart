// The versions screen lists Downloaded and Available separately, each by name.
// Tapping a downloaded version makes it the default; its menu only removes.
// The reader shows whatever was chosen when you come back to it.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:notify/core/navigation/routes.dart';
import 'package:notify/core/theme/app_theme.dart';
import 'package:notify/features/bible/data/bible_repository.dart';
import 'package:notify/features/bible/data/bible_version_state_repository.dart';
import 'package:notify/features/bible/domain/models/bible_book_entity.dart';
import 'package:notify/features/bible/domain/models/bible_version_info.dart';
import 'package:notify/features/bible/presentation/providers/bible_chapter_providers.dart';
import 'package:notify/features/bible/presentation/providers/bible_providers.dart';
import 'package:notify/features/bible/presentation/providers/verse_tag_providers.dart';
import 'package:notify/features/bible/presentation/screens/bible_chapter_screen.dart';
import 'package:notify/features/bible/presentation/screens/bible_versions_screen.dart';
import 'package:notify/l10n/app_localizations.dart';

BibleVersionInfo _v(String code, String name,
        {bool downloaded = false, bool isDefault = false}) =>
    BibleVersionInfo(
      code: code,
      name: name,
      downloadUrl: 'https://example.test/$code',
      approximateSizeMb: 8,
      sortOrder: 1,
      isDefault: isDefault,
      isDownloaded: downloaded,
    );

class _FakeStates implements BibleVersionStateRepository {
  final defaults = <String>[];

  @override
  Future<bool> isCacheFresh() async => true; // skip the network refresh

  @override
  Future<void> setDefault(String code) async => defaults.add(code);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

Future<_FakeStates> _pumpVersions(
  WidgetTester tester,
  List<BibleVersionInfo> versions,
) async {
  final repo = _FakeStates();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      bibleVersionStateRepositoryProvider.overrideWithValue(repo),
      bibleVersionStatesProvider
          .overrideWith((ref) => Stream.value(versions)),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const BibleVersionsScreen(),
    ),
  ));
  await tester.pump();
  await tester.pump();
  return repo;
}

double _top(WidgetTester tester, String text) =>
    tester.getTopLeft(find.text(text)).dy;

void main() {
  final versions = [
    _v('ZZ', 'Zeta Bible', downloaded: true),
    _v('AV', 'amplified version'),
    _v('BB', 'Beta Bible', downloaded: true, isDefault: true),
    _v('GG', 'Gamma Bible'),
    _v('KK', 'Kappa Bible', downloaded: true),
  ];

  test('sortedByName orders by name, ignoring case', () {
    final names = sortedByName(versions).map((v) => v.name).toList();
    expect(names, [
      'amplified version',
      'Beta Bible',
      'Gamma Bible',
      'Kappa Bible',
      'Zeta Bible',
    ]);
  });

  testWidgets('two sections, Downloaded then Available, each by name',
      (tester) async {
    await _pumpVersions(tester, versions);

    expect(find.text('Downloaded'), findsOneWidget);
    expect(find.text('Available'), findsOneWidget);

    final order = [
      _top(tester, 'Downloaded'),
      _top(tester, 'Beta Bible'),
      _top(tester, 'Kappa Bible'),
      _top(tester, 'Zeta Bible'),
      _top(tester, 'Available'),
      _top(tester, 'amplified version'),
      _top(tester, 'Gamma Bible'),
    ];
    final sorted = [...order]..sort();
    expect(order, sorted, reason: 'sections and names must read in this order');
  });

  testWidgets('a section with nothing in it is not shown', (tester) async {
    await _pumpVersions(tester, [_v('AV', 'Alpha'), _v('BB', 'Beta')]);
    expect(find.text('Downloaded'), findsNothing);
    expect(find.text('Available'), findsOneWidget);
  });

  testWidgets('tapping a downloaded version makes it the default',
      (tester) async {
    final repo = await _pumpVersions(tester, versions);

    await tester.tap(find.text('Kappa Bible'));
    await tester.pump();

    expect(repo.defaults, ['KK']);
  });

  testWidgets('tapping the current default, or an undownloaded one, does not',
      (tester) async {
    final repo = await _pumpVersions(tester, versions);

    await tester.tap(find.text('Beta Bible'));
    await tester.tap(find.text('Gamma Bible'));
    await tester.pump();

    expect(repo.defaults, isEmpty);
    expect(find.text('Download'), findsNWidgets(2));
  });

  testWidgets('the row menu only offers Remove', (tester) async {
    await _pumpVersions(tester, versions);

    await tester.tap(find.byTooltip('More options').first);
    await tester.pumpAndSettle();

    expect(find.text('Remove'), findsOneWidget);
    expect(find.text('Set as default'), findsNothing);
  });

  testWidgets('the reader shows the version chosen on the versions screen',
      (tester) async {
    tester.view.physicalSize = const Size(360, 740) * 3;
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final states = StreamController<List<BibleVersionInfo>>();
    addTearDown(() => unawaited(states.close()));
    states.add([
      _v('KJV', 'King James', downloaded: true, isDefault: true),
      _v('NIV', 'New International', downloaded: true),
    ]);

    final router = GoRouter(routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => const BibleChapterScreen(
            bookId: 52, chapter: 5, initialTranslation: 'KJV'),
      ),
      GoRoute(
        path: Routes.bibleVersions,
        builder: (context, _) => Scaffold(
          body: TextButton(
            onPressed: () {
              // What tapping NIV on the real screen does to the default.
              states.add([
                _v('KJV', 'King James', downloaded: true),
                _v('NIV', 'New International',
                    downloaded: true, isDefault: true),
              ]);
              context.pop();
            },
            child: const Text('choose NIV'),
          ),
        ),
      ),
    ]);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        bibleRepositoryProvider.overrideWithValue(_FakeRepo()),
        bibleTranslationsProvider.overrideWithValue(['KJV', 'NIV']),
        bibleVersionStatesProvider.overrideWith((ref) => states.stream),
        bibleVersesProvider.overrideWith((ref, p) => []),
        bibleChaptersProvider.overrideWith((ref, p) => [1, 2, 3, 4, 5]),
        bibleBooksProvider.overrideWithValue([]),
        chapterHighlightsProvider.overrideWith((ref, p) => Stream.value([])),
        chapterVerseTagsProvider
            .overrideWith((ref, p) => <int, Set<String>>{}),
      ],
      child: MaterialApp.router(
        theme: AppTheme.light(),
        routerConfig: router,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ));
    await tester.pump(const Duration(milliseconds: 200));

    // The pill shows the version being read.
    final pill = find.descendant(
        of: find.byType(AppBar), matching: find.text('KJV'));
    expect(pill, findsOneWidget);

    await tester.tap(pill); // opens the versions screen
    await tester.pumpAndSettle();
    await tester.tap(find.text('choose NIV'));
    await tester.pumpAndSettle();

    expect(
        find.descendant(of: find.byType(AppBar), matching: find.text('NIV')),
        findsOneWidget);
    expect(
        find.descendant(of: find.byType(AppBar), matching: find.text('KJV')),
        findsNothing);
  });

  testWidgets(
      'a default that finishes loading does not override the version a '
      'chapter was opened in', (tester) async {
    tester.view.physicalSize = const Size(360, 740) * 3;
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final states = StreamController<List<BibleVersionInfo>>();
    addTearDown(() => unawaited(states.close()));

    final router = GoRouter(routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => const BibleChapterScreen(
            bookId: 52, chapter: 5, initialTranslation: 'NIV'),
      ),
    ]);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        bibleRepositoryProvider.overrideWithValue(_FakeRepo()),
        bibleTranslationsProvider.overrideWithValue(['KJV', 'NIV']),
        bibleVersionStatesProvider.overrideWith((ref) => states.stream),
        bibleVersesProvider.overrideWith((ref, p) => []),
        bibleChaptersProvider.overrideWith((ref, p) => [1, 2, 3, 4, 5]),
        bibleBooksProvider.overrideWithValue([]),
        chapterHighlightsProvider.overrideWith((ref, p) => Stream.value([])),
        chapterVerseTagsProvider
            .overrideWith((ref, p) => <int, Set<String>>{}),
      ],
      child: MaterialApp.router(
        theme: AppTheme.light(),
        routerConfig: router,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ));
    await tester.pump(const Duration(milliseconds: 200));

    states.add([
      _v('KJV', 'King James', downloaded: true, isDefault: true),
      _v('NIV', 'New International', downloaded: true),
    ]);
    await tester.pump(const Duration(milliseconds: 200));

    expect(
        find.descendant(of: find.byType(AppBar), matching: find.text('NIV')),
        findsOneWidget,
        reason: 'opened from a NIV verse, it stays NIV');
  });
}

class _FakeRepo implements BibleRepository {
  @override
  BibleBookEntity? getBookById(int bookId) => const BibleBookEntity(
        id: 52,
        name: '1 Thessalonians',
        shortName: '1Th',
        testament: 1,
        sortOrder: 52,
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
