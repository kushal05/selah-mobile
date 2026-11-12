// The versions screen lists Downloaded and Available separately, each by name.
// Tapping a downloaded version makes it the default; its menu only removes.
// The reader shows whatever was chosen when you come back to it.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:notify/core/sync/providers/sync_providers.dart';
import 'package:go_router/go_router.dart';

import 'package:notify/core/navigation/routes.dart';
import 'package:notify/core/theme/app_theme.dart';
import 'package:notify/features/bible/data/bible_repository.dart';
import 'package:notify/features/bible/data/bible_version_state_repository.dart';
import 'package:notify/features/bible/domain/models/bible_book_entity.dart';
import 'package:notify/features/bible/domain/models/bible_version_info.dart';
import 'package:notify/features/bible/presentation/providers/bible_chapter_providers.dart';
import 'package:notify/features/bible/presentation/providers/bible_download_manager.dart';
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
  List<BibleVersionInfo> versions, {
  Set<String> updates = const {},
  BibleDownloadRunner? updateRunner,
}) async {
  final repo = _FakeStates();
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      bibleVersionStateRepositoryProvider.overrideWithValue(repo),
      bibleVersionStatesProvider
          .overrideWith((ref) => Stream.value(versions)),
      bibleVersionUpdatesProvider.overrideWith((ref) async => updates),
      if (updateRunner != null)
        bibleUpdateRunnerProvider.overrideWithValue(updateRunner),
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
  _updateTests();

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

  testWidgets('a tap on a downloaded row can be seen: the splash is inside the '
      'card, not under its background', (tester) async {
    await _pumpVersions(tester, versions);

    for (final name in ['Kappa Bible', 'Beta Bible']) {
      final ink = find.ancestor(
          of: find.text(name), matching: find.byType(InkWell));
      expect(ink, findsOneWidget, reason: '$name has a tappable row');
      expect(tester.widget<InkWell>(ink).onTap, isNotNull,
          reason: 'even the current default answers a touch');

      // The nearest Material is the row's own, within the card's clip. The
      // screen's Material is behind the card background, so a splash there is
      // never seen.
      final material = find.ancestor(of: ink, matching: find.byType(Material)).first;
      expect(find.ancestor(of: material, matching: find.byType(ClipRRect)),
          findsWidgets);
      expect(tester.widget<Material>(material).color, Colors.transparent);
    }
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

    SharedPreferences.setMockInitialValues({});

    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(ProviderScope(
      overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
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

    SharedPreferences.setMockInitialValues({});

    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(ProviderScope(
      overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
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


// ─── Updates ──────────────────────────────────────────────────────────────────

void _updateTests() {
  final versions = [
    BibleVersionInfo(
        code: 'TLB',
        name: 'The Living Bible',
        downloadUrl: 'https://example.test/TLB',
        approximateSizeMb: 12,
        sortOrder: 1,
        isDefault: false,
        isDownloaded: true),
    BibleVersionInfo(
        code: 'NIV',
        name: 'New International',
        downloadUrl: 'https://example.test/NIV',
        approximateSizeMb: 12,
        sortOrder: 2,
        isDefault: false,
        isDownloaded: true),
  ];

  testWidgets('a version with a newer file says so and offers Update',
      (tester) async {
    await _pumpVersions(tester, versions, updates: {'TLB'});
    await tester.pump();

    expect(find.text('A newer, more complete copy is available'),
        findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Update'), findsOneWidget,
        reason: 'only TLB has one');
  });

  testWidgets('no update, no button and no note', (tester) async {
    await _pumpVersions(tester, versions);
    await tester.pump();

    expect(find.text('A newer, more complete copy is available'),
        findsNothing);
    expect(find.widgetWithText(OutlinedButton, 'Update'), findsNothing);
  });

  testWidgets('Update runs the update download, not a plain one',
      (tester) async {
    final calls = <String>[];
    await _pumpVersions(
      tester,
      versions,
      updates: {'TLB'},
      updateRunner: (info, onProgress) async => calls.add(info.code),
    );
    await tester.pump();

    await tester.tap(find.widgetWithText(OutlinedButton, 'Update'));
    await tester.pump();
    await tester.pump();

    expect(calls, ['TLB']);
  });

  testWidgets('Remove is still there beside Update', (tester) async {
    await _pumpVersions(tester, versions, updates: {'TLB'});
    await tester.pump();

    await tester.tap(find.byTooltip('More options').first);
    await tester.pumpAndSettle();
    expect(find.text('Remove'), findsOneWidget);
  });

  testWidgets('a failed update says so on the row', (tester) async {
    await _pumpVersions(
      tester,
      versions,
      updates: {'TLB'},
      updateRunner: (info, onProgress) async => throw StateError('offline'),
    );
    await tester.pump();

    await tester.tap(find.widgetWithText(OutlinedButton, 'Update'));
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('Download failed'), findsOneWidget);
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
