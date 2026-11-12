// The chapter screen's title used to wrap beside four actions at phone width
// and lose the chapter number. It is now one line, book name ellipsised first,
// tappable for the chapter picker; the version pill opens the downloader.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:notify/core/sync/providers/sync_providers.dart';
import 'package:go_router/go_router.dart';

import 'package:notify/core/navigation/routes.dart';
import 'package:notify/core/theme/app_theme.dart';
import 'package:notify/features/bible/data/bible_repository.dart';
import 'package:notify/features/bible/domain/models/bible_book_entity.dart';
import 'package:notify/features/bible/presentation/providers/bible_chapter_providers.dart';
import 'package:notify/features/bible/presentation/providers/bible_providers.dart';
import 'package:notify/features/bible/presentation/providers/verse_tag_providers.dart';
import 'package:notify/features/bible/presentation/screens/bible_chapter_screen.dart';
import 'package:notify/features/bible/presentation/widgets/chapter_picker_sheet.dart';
import 'package:notify/l10n/app_localizations.dart';

class _FakeRepo implements BibleRepository {
  @override
  BibleBookEntity? getBookById(int bookId) => const BibleBookEntity(
        id: 52,
        name: '1 Thessalonians and a very long suffix',
        shortName: '1Th',
        testament: 1,
        sortOrder: 52,
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

Future<void> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(360, 740) * 3;
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  final router = GoRouter(routes: [
    GoRoute(
      path: '/',
      builder: (_, _) => const BibleChapterScreen(
        bookId: 52,
        chapter: 5,
        initialTranslation: 'KJV',
      ),
    ),
    GoRoute(
      path: Routes.bibleVersions,
      builder: (_, _) => const Scaffold(body: Text('versions-screen')),
    ),
  ]);

  SharedPreferences.setMockInitialValues({});

  final prefs = await SharedPreferences.getInstance();

  await tester.pumpWidget(ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      bibleRepositoryProvider.overrideWithValue(_FakeRepo()),
      bibleTranslationsProvider.overrideWithValue(['KJV', 'NIV']),
      bibleVersesProvider.overrideWith((ref, p) => []),
      bibleChaptersProvider.overrideWith((ref, p) => [1, 2, 3, 4, 5]),
      bibleBooksProvider.overrideWithValue([]),
      chapterHighlightsProvider.overrideWith((ref, p) => Stream.value([])),
      chapterVerseTagsProvider.overrideWith((ref, p) => <int, Set<String>>{}),
    ],
    child: MaterialApp.router(
      theme: AppTheme.light(),
      routerConfig: router,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
    ),
  ));
  await tester.pump(const Duration(milliseconds: 200));
}

void main() {
  testWidgets('long book name ellipsises; chapter number stays visible',
      (tester) async {
    await _pump(tester);

    final chapter = find.descendant(
        of: find.byType(AppBar), matching: find.text(' 5'));
    expect(chapter, findsOneWidget);
    final box = tester.getRect(chapter);
    expect(box.right, lessThanOrEqualTo(360));
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping the title opens the chapter picker', (tester) async {
    await _pump(tester);
    await tester.tap(find.descendant(
        of: find.byType(AppBar), matching: find.text(' 5')));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(ChapterPickerSheet), findsOneWidget);
  });

  testWidgets('tapping the version pill opens the versions screen',
      (tester) async {
    await _pump(tester);
    await tester.tap(find.descendant(
        of: find.byType(AppBar), matching: find.text('KJV')));
    await tester.pumpAndSettle();
    expect(find.text('versions-screen'), findsOneWidget);
  });
}
