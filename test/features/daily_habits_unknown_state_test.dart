// The widget rendered "nothing done yet" for three different situations:
// loaded-and-empty, still loading, and failed to load. Only one of those is
// true, and the mistake is destructive rather than cosmetic — toggleToday
// re-reads the database instead of trusting the UI, so tapping a habit that
// is really completed but drawn as not-done soft-deletes the completion. A
// tap meant to record something destroys it.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:notify/core/theme/app_theme.dart';
import 'package:notify/l10n/app_localizations.dart';
import 'package:notify/features/habits/data/habit_log_repository.dart';
import 'package:notify/features/home/presentation/providers/habit_providers.dart';
import 'package:notify/features/home/presentation/widgets/daily_habits_widget.dart';

/// Records toggleToday calls without touching a database.
///
/// The point of the test is that the *write* never happens, not merely that
/// the tile announces itself as inert — a sighted tap would still reach
/// toggleToday if only the semantics flag were changed.
class SpyRepo implements HabitLogRepository {
  final toggled = <HabitType>[];

  @override
  Future<bool> toggleToday(HabitType habit) async {
    toggled.add(habit);
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

late SpyRepo spy;

Future<void> pumpHabits(WidgetTester tester, Stream<Set<String>> stream) async {
  spy = SpyRepo();
  tester.view.physicalSize = const Size(402, 874) * 3;
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(ProviderScope(
    overrides: [
      todayHabitKeysProvider.overrideWith((ref) => stream),
      habitLogRepositoryProvider.overrideWithValue(spy),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const Scaffold(
        body: SingleChildScrollView(child: DailyHabitsWidget()),
      ),
    ),
  ));
  await tester.pump();
}

/// The habit tiles' own Semantics nodes.
///
/// Scoped by label rather than by widget type: the header's "View All" is a
/// GestureDetector inside this widget too and is always tappable, so a naive
/// search for tappable descendants says "yes" no matter what the tiles do.
Iterable<Semantics> tileSemantics(WidgetTester tester) => tester
    .widgetList<Semantics>(find.descendant(
      of: find.byType(DailyHabitsWidget),
      matching: find.byType(Semantics),
    ))
    .where((s) => (s.properties.label ?? '').contains('Bible Reading'));

/// Whether any habit tile presents itself as something you can act on.
bool anyTileTappable(WidgetTester tester) =>
    tileSemantics(tester).any((s) => s.properties.button == true);

void main() {
  testWidgets('a habit cannot be toggled while the state is still unknown',
      (tester) async {
    // A stream that has not produced anything yet: the loading case.
    await pumpHabits(tester, StreamController<Set<String>>().stream);

    expect(anyTileTappable(tester), isFalse,
        reason: 'a tap here toggles against a completion we have not read');
  });

  testWidgets('nor when the read failed outright', (tester) async {
    await pumpHabits(
        tester, Stream<Set<String>>.error(Exception('db unavailable')));
    await tester.pump();

    expect(anyTileTappable(tester), isFalse);
  });

  testWidgets('a failed read says so, and offers a retry', (tester) async {
    await pumpHabits(
        tester, Stream<Set<String>>.error(Exception('db unavailable')));
    await tester.pump();

    expect(find.text("Today's habits couldn't be loaded"), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('tapping an unknown tile does not reach the write at all',
      (tester) async {
    await pumpHabits(
        tester, Stream<Set<String>>.error(Exception('db unavailable')));
    await tester.pump();

    await tester.tap(find.text('Bible Reading'), warnIfMissed: false);
    await tester.pump();

    expect(spy.toggled, isEmpty,
        reason: 'toggleToday re-reads the database and would delete a '
            'completion we never managed to read');
  });

  testWidgets('once the state is known, the tiles work again', (tester) async {
    await pumpHabits(tester, Stream.value(<String>{'bible_reading'}));
    await tester.pump();

    expect(anyTileTappable(tester), isTrue);
    expect(find.text("Today's habits couldn't be loaded"), findsNothing);
  });
}
