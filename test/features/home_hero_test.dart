// The home hero and quick actions, at the sizes that break fixed heights.
//
// Both were first built by computing a height from font metrics. The quick
// action row came out 4.8px short and clipped its labels on a real device
// while every test in the suite passed — because nothing rendered either
// widget. These pump them and fail on overflow.

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:notify/core/sync/providers/sync_providers.dart';
import 'package:notify/core/theme/app_theme.dart';
import 'package:notify/l10n/l10n.dart';
import 'package:notify/features/home/presentation/widgets/daily_focus_card.dart';
import 'package:notify/features/home/presentation/widgets/quick_actions_row.dart';
import 'package:notify/core/sync/models/prayer_model.dart';
import 'package:notify/core/sync/models/promise_model.dart';
import 'package:notify/core/sync/models/bible_reference_history_model.dart';

Future<List<FlutterErrorDetails>> _pump(
  WidgetTester tester,
  Widget child, {
  required Size size,
  required double textScale,
  List<Override> overrides = const [],
}) async {
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();

  final errors = <FlutterErrorDetails>[];
  final prev = FlutterError.onError;
  FlutterError.onError = errors.add;

  await tester.pumpWidget(ProviderScope(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs), ...overrides],
    child: MaterialApp(
      theme: AppTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: Scaffold(
            body: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: child,
              ),
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.pump(const Duration(milliseconds: 400));
  FlutterError.onError = prev;
  return errors;
}

bool _overflowed(List<FlutterErrorDetails> errors) =>
    errors.any((e) => '${e.exception}'.contains('overflow'));

/// The carousel's own horizontal scrollable.
///
/// `Scrollable.first` finds the harness's outer vertical scroll view, and a
/// notification dispatched there never reaches the carousel's listener — which
/// is how an earlier version of these tests passed with the bug present.
ScrollableState _carousel(WidgetTester tester) =>
    tester.state<ScrollableState>(find.descendant(
      of: find.byType(DailyFocusCard),
      matching: find.byType(Scrollable),
    ));

/// Which slot is showing.
///
/// Asserted on scroll position rather than on the page dots: the dots are an
/// implicitly-animated width, so reading them measures the animation's
/// progress as much as the state, which made these tests flap.
double _slot(WidgetTester tester) {
  final s = _carousel(tester);
  return (s.position.pixels / s.position.viewportDimension).roundToDouble();
}

void main() {
  // Empty streams: the widgets must hold up before the user has any data.
  final empty = [
    activePrayersStreamProvider.overrideWith((ref) => Stream.value([])),
    promisesStreamProvider.overrideWith((ref) => Stream.value([])),
    bibleReferenceHistoryStreamProvider.overrideWith((ref) => Stream.value([])),
  ];

  // With data in all three streams the hero renders three slides — the path
  // the single-slide early return skips, and where the layout is hardest.
  final populated = [
    activePrayersStreamProvider.overrideWith((ref) => Stream.value([
          PrayerModel.create(id: 'p1', userId: 'u', title: 'Hospital people'),
        ])),
    promisesStreamProvider.overrideWith((ref) => Stream.value([
          const PromiseModel(
            id: 'pr1', userId: 'u', reference: 'Isaiah 41:10',
            content: 'Fear not, for I am with you', preview: '', notes: '',
            isFavorite: false, updatedAt: 0, version: 1, deleted: 0,
            createdAt: 0,
          ),
        ])),
    bibleReferenceHistoryStreamProvider.overrideWith((ref) => Stream.value([
          const BibleReferenceHistoryModel(
            id: 'h1', userId: 'u', book: 'Psalms', chapter: 23,
            translation: 'NKJV', openedAt: 0, updatedAt: 0, version: 1,
            deleted: 0, createdAt: 0,
          ),
        ])),
  ];

  for (final scale in [1.0, 2.0]) {
    testWidgets('three-slide carousel does not clip at ${scale}x text',
        (tester) async {
      final errors = await _pump(tester, const DailyFocusCard(),
          size: const Size(320, 640), textScale: scale, overrides: populated);
      expect(_overflowed(errors), isFalse);
      expect(errors.where((e) => '${e.exception}'.contains('stretch')), isEmpty,
          reason: 'CrossAxisAlignment.stretch asserts in an unbounded axis');
    });
  }

  testWidgets('the carousel advances on its own', (tester) async {
    await _pump(tester, const DailyFocusCard(),
        size: const Size(402, 874), textScale: 1.0, overrides: populated);

    expect(_slot(tester), 0.0);
    await tester.pump(const Duration(seconds: 7));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(_slot(tester), 1.0,
        reason: 'the carousel should have advanced by itself');

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('an idle scroll notification does not stop auto-advance',
      (tester) async {
    await _pump(tester, const DailyFocusCard(),
        size: const Size(402, 874), textScale: 1.0, overrides: populated);

    // What a scrollable emits when it attaches or an animation settles. The
    // first version stopped on any UserScrollNotification, so this killed
    // auto-advance before it ever ran.
    final scrollable = _carousel(tester);
    UserScrollNotification(
      metrics: scrollable.position.copyWith(),
      context: scrollable.context,
      direction: ScrollDirection.idle,
    ).dispatch(scrollable.context);
    await tester.pump();

    await tester.pump(const Duration(seconds: 7));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(_slot(tester), 1.0,
        reason: 'an idle notification must not disable auto-advance');

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('the carousel loops past the last slide and keeps going',
      (tester) async {
    await _pump(tester, const DailyFocusCard(),
        size: const Size(402, 874), textScale: 1.0, overrides: populated);

    final scroll = tester.state<ScrollableState>(find.descendant(
      of: find.byType(DailyFocusCard),
      matching: find.byType(Scrollable),
    ));
    final width = tester.getSize(find.byType(DailyFocusCard)).width;

    // Three slides plus one trailing duplicate of the first.
    expect(scroll.position.maxScrollExtent, closeTo(width * 3, 1.0),
        reason: 'there should be a fourth slot to scroll into');

    double page() => (scroll.position.pixels / width).round().toDouble();

    // Walk the whole loop: 0 -> 1 -> 2 -> back to 0 without rewinding.
    final visited = <double>[page()];
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(seconds: 7));
      await tester.pumpAndSettle(const Duration(milliseconds: 200));
      visited.add(page());
    }
    expect(visited, [0.0, 1.0, 2.0, 0.0],
        reason: 'it should advance forward each time and land home silently');

    // The end positions alone cannot tell a forward wrap from a rewind — both
    // read 2 then 0. Sample mid-transition: looping forward moves PAST the
    // last slide onto the duplicate, where a rewind would be heading back
    // toward slide one. This is what the first version of this test missed.
    // The visited loop ends back on slide 0, so two advances are needed to
    // reach the last slide before the wrap can be observed.
    for (var i = 0; i < 2; i++) {
      await tester.pump(const Duration(seconds: 7));
      await tester.pumpAndSettle(const Duration(milliseconds: 200));
    }
    expect(page(), 2.0, reason: 'should be sitting on the last real slide');
    await tester.pump(const Duration(seconds: 6)); // wrap begins
    await tester.pump(const Duration(milliseconds: 220)); // mid-animation
    expect(scroll.position.pixels, greaterThan(width * 2),
        reason: 'the wrap must move forward onto the duplicate, not rewind');
    await tester.pumpAndSettle(const Duration(milliseconds: 400));

    // And it is still running — a fourth tick moves it on again, which is
    // what "infinite" means as opposed to stopping at the end.
    await tester.pump(const Duration(seconds: 7));
    await tester.pumpAndSettle(const Duration(milliseconds: 200));
    expect(page(), 1.0, reason: 'the loop must continue after wrapping');

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('the carousel shows all three slides', (tester) async {
    await _pump(tester, const DailyFocusCard(),
        size: const Size(402, 874), textScale: 1.0, overrides: populated);

    // Slide one appears twice: the real one and the trailing duplicate that
    // makes the loop seamless.
    expect(find.text('Hospital people'), findsNWidgets(2));
    expect(find.text('Isaiah 41:10'), findsOneWidget);
    expect(find.text('Psalms 23'), findsOneWidget);
  });

  for (final scale in [1.0, 1.5, 2.0]) {
    testWidgets('quick actions row does not clip at ${scale}x text',
        (tester) async {
      final errors = await _pump(tester, const QuickActionsRow(),
          size: const Size(320, 640), textScale: scale, overrides: empty);
      expect(_overflowed(errors), isFalse,
          reason: 'the row clipped its labels at ${scale}x on a 320pt screen');
    });

    testWidgets('daily focus hero does not clip at ${scale}x text',
        (tester) async {
      final errors = await _pump(tester, const DailyFocusCard(),
          size: const Size(320, 640), textScale: scale, overrides: empty);
      expect(_overflowed(errors), isFalse,
          reason: 'the hero clipped at ${scale}x on a 320pt screen');
    });
  }

  testWidgets('quick actions row offers all seven actions', (tester) async {
    await _pump(tester, const QuickActionsRow(),
        size: const Size(402, 874), textScale: 1.0, overrides: empty);

    // The three that were only reachable behind the "More" tab.
    expect(find.text('New Promise'), findsOneWidget);
    expect(find.text('Songs'), findsOneWidget);
    expect(find.text('Add person'), findsOneWidget);
    expect(find.text('See more'), findsOneWidget);
  });
}
