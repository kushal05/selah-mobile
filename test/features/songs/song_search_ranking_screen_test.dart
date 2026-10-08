// The search screen shows ranked results: a title match above a song found
// only by its tag, and a card lists the tag that matched before its others.
// Real database and repositories, so this pins the wiring, not just the ranker.

import 'package:drift/drift.dart' show driftRuntimeOptions, Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:notify/core/database/sync_database.dart';
import 'package:notify/core/sync/providers/sync_providers.dart';
import 'package:notify/features/songs/presentation/screens/song_search_screen.dart';
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
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// A song with tags (name → weight).
  Future<void> song(WidgetTester tester, String title, Map<String, int> tags) =>
      tester.runAsync(() async {
        final s = await container
            .read(songRepositoryProvider)
            .createSong(userId: _userId, title: title);
        for (final MapEntry(key: name, value: weight) in tags.entries) {
          final tag = await container
              .read(tagRepositoryProvider)
              .getOrCreateTag(name, _userId);
          final l = await container
              .read(songTagRepositoryProvider)
              .addTagToSong(songId: s.id, tagId: tag.id, userId: _userId);
          await (db.update(db.syncSongTags)..where((r) => r.id.equals(l.id)))
              .write(SyncSongTagsCompanion(weight: Value(weight)));
        }
      });

  testWidgets('typing ranks a title match above a tag-only match, and the '
      'matched tag is shown first', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    // Alphabetical order would put "A Tagged Song" first.
    await song(tester, 'A Tagged Song', {'peace': 3, 'joy': 2, 'hope': 2, 'grace': 3});
    await song(tester, 'Zion Grace', {});
    await song(tester, 'Unrelated', {'peace': 3});

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SongSearchScreen(),
      ),
    ));
    await settle(tester);

    expect(find.text('Search title, tags or lyrics...'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'grace');
    await tester.pump(const Duration(milliseconds: 300)); // debounce
    await settle(tester);

    final title = tester.getTopLeft(find.text('Zion Grace')).dy;
    final tagged = tester.getTopLeft(find.text('A Tagged Song')).dy;
    expect(title, lessThan(tagged), reason: 'a title match comes first');
    expect(find.text('Unrelated'), findsNothing);

    // Three chips fit; "grace" was the match, so it leads them.
    final chips = tester
        .widgetList<Text>(find.descendant(
            // The column holding the card's title, details and chips.
            of: find
                .ancestor(of: find.text('A Tagged Song'), matching: find.byType(Column))
                .first,
            matching: find.byType(Text)))
        .map((t) => t.data)
        .toList();
    final graceAt = chips.indexOf('grace');
    expect(graceAt, isNot(-1), reason: 'the matched tag is among the chips');
    for (final other in ['peace', 'joy', 'hope']) {
      final at = chips.indexOf(other);
      if (at != -1) expect(graceAt, lessThan(at));
    }
  });
}
