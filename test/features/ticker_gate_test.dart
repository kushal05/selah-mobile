// The hero carousel must not tick while its tab is off screen.
//
// The shell is an indexedStack, so Home stays mounted while the reader is
// elsewhere. go_router mutes an inactive branch's tickers, but a Timer is not
// a ticker — the carousel woke every six seconds for the life of the app to
// start an animation that could not run.

import 'dart:async';

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
  testWidgets('the carousel holds still off-screen and resumes when shown', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(402, 874) * 3;
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    Widget app(bool active) => ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        activePrayersStreamProvider.overrideWith(
          (ref) => Stream.value([
            PrayerModel.create(id: 'p1', userId: 'u', title: 'A'),
          ]),
        ),
        promisesStreamProvider.overrideWith(
          (ref) => Stream.value([
            const PromiseModel(
              id: 'pr1',
              userId: 'u',
              reference: 'B',
              content: 'x',
              preview: '',
              notes: '',
              isFavorite: false,
              updatedAt: 0,
              version: 1,
              deleted: 0,
              createdAt: 0,
            ),
          ]),
        ),
        bibleReferenceHistoryStreamProvider.overrideWith(
          (ref) => Stream.value([
            const BibleReferenceHistoryModel(
              id: 'h1',
              userId: 'u',
              book: 'Psalms',
              chapter: 23,
              translation: 'NKJV',
              openedAt: 0,
              updatedAt: 0,
              version: 1,
              deleted: 0,
              createdAt: 0,
            ),
          ]),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        // What go_router does to a branch it is not showing.
        home: TickerMode(
          enabled: active,
          child: Scaffold(
            body: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: const DailyFocusCard(),
              ),
            ),
          ),
        ),
      ),
    );

    double pos() => tester
        .state<ScrollableState>(
          find.descendant(
            of: find.byType(DailyFocusCard),
            matching: find.byType(Scrollable),
          ),
        )
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
    expect(
      pos(),
      greaterThan(start),
      reason: 'it must resume once the tab is shown again',
    );

    await tester.pumpWidget(const SizedBox.shrink());
  });

  // The carousel is documented to stop "permanently once the reader swipes".
  // The visibility gate restarts the timer whenever it finds it stopped, so
  // *any* rebuild after a swipe took the carousel back off the reader — and
  // this widget rebuilds whenever sync pushes new prayers, promises or Bible
  // history. That is the rebuild driven here.
  testWidgets('a reader swipe stops the carousel for good', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    // Controlled so the test can push an emission after the swipe, the way a
    // sync pull would.
    final promises = StreamController<List<PromiseModel>>.broadcast();
    addTearDown(promises.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          activePrayersStreamProvider.overrideWith(
            (ref) => Stream.value(const []),
          ),
          promisesStreamProvider.overrideWith(
            (ref) => _withInitial(promises.stream),
          ),
          bibleReferenceHistoryStreamProvider.overrideWith(
            (ref) => Stream.value([
              BibleReferenceHistoryModel(
                id: 'h1',
                userId: 'u',
                book: 'Psalms',
                chapter: 23,
                translation: 'NKJV',
                openedAt: 0,
                updatedAt: 0,
                version: 1,
                deleted: 0,
                createdAt: 0,
              ),
            ]),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: const DailyFocusCard(),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));

    final scrollable = find.descendant(
      of: find.byType(DailyFocusCard),
      matching: find.byType(Scrollable),
    );
    double pos() => tester.state<ScrollableState>(scrollable).position.pixels;

    // The reader takes over.
    await tester.drag(scrollable, const Offset(-160, 0));
    await tester.pumpAndSettle();

    // Sync delivers something; the widget rebuilds.
    promises.add(const []);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    final afterRebuild = pos();

    // Long enough for two auto-advance ticks to have fired.
    await tester.pump(const Duration(seconds: 14));
    await tester.pumpAndSettle(const Duration(milliseconds: 600));

    expect(
      pos(),
      afterRebuild,
      reason: 'a rebuild must not restart auto-advance after a swipe',
    );

    await tester.pumpWidget(const SizedBox.shrink());
  });

  // A brand-new user has no promises and no reading history. That used to
  // produce a carousel of exactly one slide — unswipeable, pointing at nothing
  // else in the app — and it returned before the LayoutBuilder that holds the
  // TickerMode gate, so the 6-second timer ran forever for the users with the
  // least to look at.
  testWidgets('a new user still gets a full carousel that can be stilled', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    Widget app(bool active) => ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        activePrayersStreamProvider.overrideWith(
          (ref) => Stream.value(const []),
        ),
        promisesStreamProvider.overrideWith((ref) => Stream.value(const [])),
        bibleReferenceHistoryStreamProvider.overrideWith(
          (ref) => Stream.value(const []),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: TickerMode(
          enabled: active,
          child: Scaffold(
            body: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: const DailyFocusCard(),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpWidget(app(true));
    await tester.pump(const Duration(milliseconds: 400));

    // Prayer, promise and reading slides all present, each with its own action.
    // All three slides render, each with its own call to action, rather than
    // the promise and reading ones vanishing.
    // The row pads with a clone of the first and last slide, so each
    // label can legitimately appear more than once.
    expect(find.text('Add Prayer'), findsWidgets);
    expect(
      find.text('Add a promise'),
      findsWidgets,
      reason: 'an empty promises list must become an invitation, not a gap',
    );
    expect(
      find.text('Open Bible'),
      findsWidgets,
      reason: 'no reading history must become an invitation, not a gap',
    );

    final scrollable = find.descendant(
      of: find.byType(DailyFocusCard),
      matching: find.byType(Scrollable),
    );
    expect(
      scrollable,
      findsOneWidget,
      reason: 'an empty account must still get a scrollable carousel',
    );

    double pos() => tester.state<ScrollableState>(scrollable).position.pixels;

    // Off-screen, the timer must stop — which is only reachable now that the
    // single-slide early return no longer applies.
    await tester.pumpWidget(app(false));
    await tester.pump(const Duration(milliseconds: 200));
    final parked = pos();
    await tester.pump(const Duration(seconds: 14));
    await tester.pumpAndSettle(const Duration(milliseconds: 400));
    expect(
      pos(),
      parked,
      reason: 'an off-screen carousel must not advance, even for a new user',
    );

    await tester.pumpWidget(const SizedBox.shrink());
  });
}

/// Emits an empty list immediately, then whatever [source] pushes — the shape
/// a Drift watch() has, without pulling in rxdart for one operator.
Stream<List<PromiseModel>> _withInitial(
  Stream<List<PromiseModel>> source,
) async* {
  yield const [];
  yield* source;
}
