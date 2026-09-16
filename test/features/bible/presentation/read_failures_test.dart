// Reads that used to report what they had not read.
//
// A failed highlights read rendered every verse unhighlighted, which does not
// look like a failure — it looks like the highlights are gone. A failed
// bookmarks read took the whole strip off the screen. A failed streak read
// said "0 days", which is a claim about the user's record.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:notify/core/sync/providers/sync_providers.dart';
import 'package:notify/core/theme/app_theme.dart';
import 'package:notify/l10n/app_localizations.dart';
import 'package:notify/features/habits/presentation/widgets/habit_stats_card.dart';
import 'package:notify/features/habits/presentation/providers/habit_analytics_providers.dart';
import 'package:notify/features/home/presentation/providers/habit_providers.dart';

Future<void> pumpStats(
  WidgetTester tester, {
  required Stream<int> streak,
}) async {
  tester.view.physicalSize = const Size(402, 874) * 3;
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();

  await tester.pumpWidget(ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      todayHabitKeysProvider.overrideWith((ref) => Stream.value(<String>{})),
      habitStreakProvider.overrideWith((ref, habit) => streak.first),
      habitBestStreakProvider.overrideWith((ref, habit) async => 5),
      habitWeeklyStatsProvider
          .overrideWith((ref, habit) async => List.filled(7, false)),
      habitHistoryProvider
          .overrideWith((ref, habit) async => <int>{}),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const Scaffold(
        body: SingleChildScrollView(
          child: HabitStatsCard(
            habit: HabitType.bible,
            icon: Icons.menu_book,
            color: Colors.blue,
          ),
        ),
      ),
    ),
  ));
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('a failed streak read does not claim the streak is zero',
      (tester) async {
    await pumpStats(tester, streak: Stream<int>.error(Exception('db down')));

    expect(find.text('0 days'), findsNothing,
        reason: "that is a statement about the user's record");
  });

  testWidgets('a real zero streak still says zero', (tester) async {
    await pumpStats(tester, streak: Stream.value(0));

    expect(find.text('0 days'), findsOneWidget);
  });

  testWidgets('a real streak is shown', (tester) async {
    await pumpStats(tester, streak: Stream.value(3));

    expect(find.text('3 days'), findsOneWidget);
  });
}
