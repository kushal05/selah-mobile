// What the prayer-activity banner says when the streak cannot be read.
//
// The banner hid its subtitle on `streak == 0`, and the screen fed it
// `valueOrNull ?? 0` — so a failed read and a streak of nought rendered the
// same banner, and someone forty days in was shown the one that means "you
// have not started".
//
// It also has three branches in one conditional expression, which is the shape
// that loses a branch to an edit and says nothing about it. That happened once
// already while this was being written.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:notify/core/sync/providers/sync_providers.dart';
import 'package:notify/core/theme/app_theme.dart';
import 'package:notify/features/habits/presentation/screens/habits_screen.dart';
import 'package:notify/l10n/l10n.dart';

Future<void> _pump(WidgetTester tester, Override streak) async {
  tester.view.physicalSize = const Size(840, 1800);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        streak,
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const HabitsScreen(),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets('a read that failed says so', (tester) async {
    await _pump(
      tester,
      prayerStreakProvider.overrideWith((ref) async => throw Exception('no db')),
    );

    expect(find.text('Streak unavailable'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a streak of nought is not called unavailable', (tester) async {
    await _pump(tester, prayerStreakProvider.overrideWith((ref) async => 0));

    expect(find.text('Streak unavailable'), findsNothing);
    // Nothing to report, and nothing claimed: the subtitle is simply absent.
    expect(find.textContaining('day streak'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a real streak is shown', (tester) async {
    await _pump(tester, prayerStreakProvider.overrideWith((ref) async => 40));

    expect(find.textContaining('40'), findsWidgets);
    expect(find.text('Streak unavailable'), findsNothing);
  });
}
