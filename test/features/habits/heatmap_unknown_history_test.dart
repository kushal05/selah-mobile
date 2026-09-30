// An unread history is not an empty one, and a loading one is not a failure.
//
// The heatmap drew ninety-one empty squares whenever the history was not
// available, which is exactly what a habit nobody has ever done looks like —
// a claim about the user's record made from a query that never returned. That
// was fixed by replacing the grid with "history unavailable".
//
// The fix then said that during loading too, because `valueOrNull` is null in
// both states. Every cold open therefore announced a failure and took it back,
// and the message is a line of text where the grid is seven rows, so each card
// grew 60px when the read landed. Found by rendering the screen and diffing it
// against the last commit.
//
// Three states, one height: loading says nothing, failure says so, and neither
// moves the card.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:notify/core/theme/app_theme.dart';
import 'package:notify/l10n/l10n.dart';
import 'package:notify/features/home/presentation/providers/habit_providers.dart';
import 'package:notify/features/habits/presentation/providers/habit_analytics_providers.dart';
import 'package:notify/features/habits/presentation/widgets/habit_stats_card.dart';

final _habit = HabitType.values.first;

Future<double> _pump(WidgetTester tester, Override override) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [override],
    child: MaterialApp(
      theme: AppTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SingleChildScrollView(
          child: HabitStatsCard(
              habit: _habit, icon: Icons.check, color: AppTheme.emerald),
        ),
      ),
    ),
  ));
  await tester.pump(const Duration(milliseconds: 300));
  return tester.getSize(find.byType(HabitStatsCard)).height;
}

Finder _message(WidgetTester tester) => find.text(
    l10n(tester.element(find.byType(HabitStatsCard))).historyUnavailable);

void main() {
  testWidgets('a history that has landed draws the grid', (tester) async {
    final h = await _pump(tester,
        habitHistoryProvider(_habit).overrideWith((ref) async => <int>{}));
    expect(_message(tester), findsNothing);
    expect(h, greaterThan(0));
  });

  testWidgets('while loading it says nothing and holds its height',
      (tester) async {
    final loading = await _pump(
      tester,
      habitHistoryProvider(_habit).overrideWith((ref) =>
          Future<Set<int>>.delayed(const Duration(seconds: 5), () => <int>{})),
    );
    expect(_message(tester), findsNothing,
        reason: 'loading is not a failure and must not be announced as one');

    // The read lands; the card must not move.
    await tester.pump(const Duration(seconds: 6));
    await tester.pump();
    final loaded = tester.getSize(find.byType(HabitStatsCard)).height;
    expect(loaded, loading,
        reason: 'the grid space must be reserved while the history is unknown');

    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('a failed read says so, at the same height', (tester) async {
    final failed = await _pump(
      tester,
      habitHistoryProvider(_habit)
          .overrideWith((ref) async => throw Exception('no database')),
    );
    expect(_message(tester), findsOneWidget,
        reason: 'a real failure must be stated, not drawn as an empty grid');

    final ok = await _pump(tester,
        habitHistoryProvider(_habit).overrideWith((ref) async => <int>{}));
    expect(failed, ok, reason: 'the message must not resize the card');
  });
}
