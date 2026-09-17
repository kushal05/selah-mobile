// Does this screen still render?
//
// Companion to screen_smoke_test.dart, covering the features the audit found
// had no test referencing them at all: songs, tags, feedback, friends, groups,
// the social people directory, bible and bible search. Same bargain — pump
// the screen with the data layer stubbed empty and fail if it throws or
// overflows — and the same reason: empty is every user's first run, and it is
// where a layout that assumes content falls over.
//
// These exist mainly as a guard on lib/core/sync/providers/sync_providers.dart.
// It is the single DI composition root for 140 providers, so renaming one is a
// silent break in whichever screen consumed it; the analyzer catches the name,
// but not a screen that now renders an error state forever.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:notify/core/sync/providers/sync_providers.dart';
import 'package:notify/core/theme/app_theme.dart';
import 'package:notify/l10n/l10n.dart';

import 'package:notify/features/bible/presentation/providers/bible_chapter_providers.dart';
import 'package:notify/features/bible/presentation/providers/bible_providers.dart';
import 'package:notify/features/bible/presentation/screens/bible_home_screen.dart';
import 'package:notify/features/bible_search/presentation/screens/bible_search_screen.dart';
import 'package:notify/features/feedback/presentation/screens/feedback_list_screen.dart';
import 'package:notify/features/friends/presentation/screens/friends_list_screen.dart';
import 'package:notify/features/groups/presentation/screens/groups_list_screen.dart';
import 'package:notify/features/search/presentation/screens/global_search_screen.dart';
import 'package:notify/features/social/presentation/screens/people_directory_screen.dart';
import 'package:notify/features/songs/presentation/screens/songs_home_screen.dart';
import 'package:notify/features/tags/presentation/screens/tag_management_screen.dart';

/// Pumps [screen] inside the app's real theme and localisations, with the data
/// layer stubbed empty.
Future<void> _pumpScreen(
  WidgetTester tester,
  Widget screen, {
  List<Override> overrides = const [],
  Size size = const Size(420, 900),
}) async {
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        ...overrides,
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: screen,
      ),
    ),
  );
  // Not pumpAndSettle: a focused field's caret animates forever.
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets('songs home renders with no songs', (tester) async {
    await _pumpScreen(
      tester,
      const SongsHomeScreen(),
      overrides: [
        songsStreamProvider.overrideWith((ref) => Stream.value(const [])),
        trashedSongsStreamProvider.overrideWith(
          (ref) => Stream.value(const []),
        ),
        songFoldersStreamProvider.overrideWith((ref) => Stream.value(const [])),
      ],
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('tag management renders with no tags', (tester) async {
    await _pumpScreen(
      tester,
      const TagManagementScreen(),
      overrides: [
        tagsStreamProvider.overrideWith((ref) => Stream.value(const [])),
        tagUsageCountsProvider.overrideWith((ref) async => const {}),
      ],
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('feedback list renders with no threads', (tester) async {
    await _pumpScreen(
      tester,
      const FeedbackListScreen(),
      overrides: [
        feedbackThreadsStreamProvider.overrideWith(
          (ref) => Stream.value(const []),
        ),
      ],
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('friends list renders with no friends', (tester) async {
    await _pumpScreen(
      tester,
      const FriendsListScreen(),
      overrides: [
        friendsListProvider.overrideWith((ref) async => const []),
        pendingRequestCountProvider.overrideWith((ref) async => 0),
      ],
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('groups list renders with no groups', (tester) async {
    await _pumpScreen(
      tester,
      const GroupsListScreen(),
      overrides: [groupsListProvider.overrideWith((ref) async => const [])],
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('people directory renders with nobody', (tester) async {
    await _pumpScreen(
      tester,
      const PeopleDirectoryScreen(),
      overrides: [
        peopleStreamProvider.overrideWith((ref) => Stream.value(const [])),
        friendsListProvider.overrideWith((ref) async => const []),
        pendingRequestCountProvider.overrideWith((ref) async => 0),
      ],
    );
    expect(tester.takeException(), isNull);
  });

  // The Bible database is downloaded on first use, not bundled, so "not yet
  // downloaded" is the state every new install starts in — and the one most
  // likely to be missed, since a developer's device has had the DB for months.
  // bibleDatabaseServiceProvider's default is an uninitialised service, which
  // is exactly that state.
  testWidgets('bible home renders before the database is downloaded', (
    tester,
  ) async {
    await _pumpScreen(
      tester,
      const BibleHomeScreen(),
      overrides: [
        bibleOldTestamentBooksProvider.overrideWithValue(const []),
        bibleNewTestamentBooksProvider.overrideWithValue(const []),
        bibleBookmarksProvider.overrideWith((ref) => Stream.value(const [])),
      ],
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('bible search renders before the database is downloaded', (
    tester,
  ) async {
    await _pumpScreen(
      tester,
      const BibleSearchScreen(),
      overrides: [
        bibleBooksProvider.overrideWithValue(const []),
        bibleTranslationsProvider.overrideWithValue(const []),
      ],
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('global search renders with an empty query', (tester) async {
    await _pumpScreen(tester, const GlobalSearchScreen());
    expect(tester.takeException(), isNull);
  });

  // The empty state is one thing; the dark palette is another, and the audit
  // found theme-migration damage that only showed on a dark ground.
  testWidgets('songs home renders in dark mode', (tester) async {
    tester.view.physicalSize = const Size(840, 1800);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          songsStreamProvider.overrideWith((ref) => Stream.value(const [])),
          trashedSongsStreamProvider.overrideWith(
            (ref) => Stream.value(const []),
          ),
          songFoldersStreamProvider.overrideWith(
            (ref) => Stream.value(const []),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const SongsHomeScreen(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);
  });
}
