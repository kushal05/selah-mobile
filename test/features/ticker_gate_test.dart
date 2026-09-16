// The hero carousel must not tick while its tab is off screen.
//
// The shell is an indexedStack, so Home stays mounted while the reader is
// elsewhere. go_router mutes an inactive branch's tickers, but a Timer is not
// a ticker — the carousel woke every six seconds for the life of the app to
// start an animation that could not run.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:notify/core/sync/providers/sync_providers.dart';
import 'package:notify/core/sync/models/prayer_model.dart';
import 'package:notify/core/sync/models/promise_model.dart';
import 'package:notify/core/sync/models/bible_reference_history_model.dart';
import 'package:notify/core/theme/app_theme.dart';
import 'package:notify/l10n/l10n.dart';
import 'package:notify/features/home/presentation/widgets/daily_focus_card.dart';

void main() {
  testWidgets('the carousel holds still off-screen and resumes when shown',
      (tester) async {
    tester.view.physicalSize = const Size(402, 874) * 3;
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    Widget app(bool active) => ProviderScope(overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          activePrayersStreamProvider.overrideWith((ref) => Stream.value([
                PrayerModel.create(id: 'p1', userId: 'u', title: 'A')])),
          promisesStreamProvider.overrideWith((ref) => Stream.value([
                const PromiseModel(id: 'pr1', userId: 'u', reference: 'B',
                  content: 'x', preview: '', notes: '', isFavorite: false,
                  updatedAt: 0, version: 1, deleted: 0, createdAt: 0)])),
          bibleReferenceHistoryStreamProvider.overrideWith((ref) =>
              Stream.value([const BibleReferenceHistoryModel(id: 'h1',
                  userId: 'u', book: 'Psalms', chapter: 23, translation: 'NKJV',
                  openedAt: 0, updatedAt: 0, version: 1, deleted: 0,
                  createdAt: 0)])),
        ], child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          // What go_router does to a branch it is not showing.
          home: TickerMode(
            enabled: active,
            child: Scaffold(body: SingleChildScrollView(
              child: Padding(padding: const EdgeInsets.all(16),
                child: const DailyFocusCard()))),
          ),
        ));

    double pos() => tester
        .state<ScrollableState>(find.descendant(
            of: find.byType(DailyFocusCard), matching: find.byType(Scrollable)))
        .position
        .pixels;

    // Inactive: no movement, however long we wait.
    //
    // This half is a regression guard, not proof the timer stopped: with
    // tickers muted the position holds still whether or not the timer fires,
    // so removing the gate does not make it fail. The half below does the
    // real work — it fails if the gate stops the timer and never restarts it,
    // which is the way this change could actually break the feature.
    await tester.pumpWidget(app(false));
    await tester.pump(const Duration(milliseconds: 400));
    final start = pos();
    await tester.pump(const Duration(seconds: 14));
    await tester.pump(const Duration(milliseconds: 500));
    expect(pos(), start, reason: 'an off-screen carousel must not advance');

    // Active: it starts again without needing a remount.
    await tester.pumpWidget(app(true));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(seconds: 7));
    await tester.pumpAndSettle(const Duration(milliseconds: 200));
    expect(pos(), greaterThan(start),
        reason: 'it must resume once the tab is shown again');

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
