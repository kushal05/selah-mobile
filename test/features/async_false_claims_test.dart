// A failed read must not be reported as a fact about the user's data.
//
// Both of these consumed an AsyncValue with `?? <default>`, which collapses
// three different situations — loaded, still loading, and failed — into one.
// The home hero then told the user they had no prayers, and the chapter
// screen's bookmark button reported "not bookmarked" and stayed live, so a
// tap ran toggleBookmark, which re-queries the database and deletes the row
// it finds.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:notify/core/theme/app_theme.dart';
import 'package:notify/core/sync/models/prayer_model.dart';
import 'package:notify/core/sync/providers/sync_providers.dart';
import 'package:notify/l10n/app_localizations.dart';
import 'package:notify/features/home/presentation/widgets/daily_focus_card.dart';

Future<void> pumpHero(
    WidgetTester tester, Stream<List<PrayerModel>> prayers) async {
  tester.view.physicalSize = const Size(402, 874) * 3;
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();

  await tester.pumpWidget(ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      activePrayersStreamProvider.overrideWith((ref) => prayers),
      promisesStreamProvider.overrideWith((ref) => Stream.value(const [])),
      bibleReferenceHistoryStreamProvider
          .overrideWith((ref) => Stream.value(const [])),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const Scaffold(
        body: SingleChildScrollView(child: DailyFocusCard()),
      ),
    ),
  ));
  await tester.pump();
}

void main() {
  testWidgets('the hero does not claim you have no prayers when it failed',
      (tester) async {
    await pumpHero(tester,
        Stream<List<PrayerModel>>.error(Exception('db unavailable')));
    await tester.pump();

    expect(find.text('No active prayers'), findsNothing,
        reason: 'that is a statement about the user\'s data we cannot make');
    expect(find.text("Your prayers couldn't be loaded"), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('nor while it is still reading', (tester) async {
    // A stream that never emits: the loading case, which happens on every
    // cold open before the first event arrives.
    await pumpHero(tester, const Stream<List<PrayerModel>>.empty());

    expect(find.text('No active prayers'), findsNothing);
    expect(find.text('Add Prayer'), findsNothing,
        reason: 'offering to add one implies we know there are none');
  });

  testWidgets('and still says so when there genuinely are none',
      (tester) async {
    await pumpHero(tester, Stream.value(const <PrayerModel>[]));
    await tester.pump();

    expect(find.text('No active prayers'), findsOneWidget);
  });

  testWidgets('the loading hero keeps the loaded card\'s height',
      (tester) async {
    // The first version of this fix rendered an empty title, subtitle and no
    // button, so the card was 137pt while reading and 228pt once loaded — a
    // 90pt jump that shoved the rest of Home down on every cold open. Being
    // right about the data is not worth being wrong about the layout.
    final ctl = StreamController<List<PrayerModel>>();
    addTearDown(ctl.close);

    await pumpHero(tester, ctl.stream);
    final loading = tester.getSize(find.byType(DailyFocusCard)).height;

    ctl.add(const <PrayerModel>[]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final loaded = tester.getSize(find.byType(DailyFocusCard)).height;

    expect((loaded - loading).abs(), lessThan(32),
        reason: 'loading $loading -> loaded $loaded is a visible jump');
  });
}
