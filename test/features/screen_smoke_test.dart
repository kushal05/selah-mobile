// Does this screen still render?
//
// Six audit passes found every defect in the interface layer, and every one
// was found by a person looking at a screen — because 64,000 lines of UI had
// no tests while 37,000 lines of sync logic had 300. These are the cheapest
// possible counterweight: pump a screen with empty data and fail if it throws
// or overflows.
//
// They would have caught the link-picker regression (a sheet with no Material
// ancestor), the Bible chapter overflow, and the bracket damage in prayer
// detail — all of which reached a human first.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:notify/core/sync/providers/sync_providers.dart';
import 'package:notify/core/theme/app_theme.dart';
import 'package:notify/l10n/l10n.dart';

import 'package:notify/features/prayers/presentation/screens/prayer_list_screen.dart';
import 'package:notify/features/habits/presentation/screens/habits_screen.dart';
import 'package:notify/features/people/presentation/screens/people_list_screen.dart';
import 'package:notify/features/promises/presentation/screens/promises_list_screen.dart';
import 'package:notify/features/auth/presentation/screens/onboarding_screen.dart';

/// Pumps [screen] inside the app's real theme and localisations, with the
/// data layer stubbed empty.
///
/// Empty is the interesting case: it is every user's first run, and it is
/// where a layout that assumes content tends to fall over.
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
  testWidgets('prayer list renders with no prayers', (tester) async {
    await _pumpScreen(
      tester,
      const PrayerListScreen(),
      overrides: [
        prayersStreamProvider.overrideWith((ref) => Stream.value(const [])),
        peopleStreamProvider.overrideWith((ref) => Stream.value(const [])),
      ],
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('prayer list renders in dark mode', (tester) async {
    tester.view.physicalSize = const Size(840, 1800);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        prayersStreamProvider.overrideWith((ref) => Stream.value(const [])),
        peopleStreamProvider.overrideWith((ref) => Stream.value(const [])),
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const PrayerListScreen(),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);
  });

  testWidgets('prayer list survives a narrow screen at large text',
      (tester) async {
    await _pumpScreen(
      tester,
      const PrayerListScreen(),
      size: const Size(320, 700),
      overrides: [
        prayersStreamProvider.overrideWith((ref) => Stream.value(const [])),
        peopleStreamProvider.overrideWith((ref) => Stream.value(const [])),
      ],
    );
    expect(tester.takeException(), isNull);
  });

  // Onboarding's four pages moved from a `static const` list to a getter that
  // reads the ARB, because it is the first copy a new user sees and a const
  // list has no BuildContext to look anything up with. That getter runs inside
  // build, on a screen whose PageController listener calls setState on every
  // scroll frame — so this pumps it, swipes it, and fails on a throw or an
  // overflow. Nothing covered this screen before.
  testWidgets('onboarding renders and swipes', (tester) async {
    await _pumpScreen(tester, const OnboardingScreen());
    expect(find.text('Welcome to Selah'), findsOneWidget);

    await tester.drag(find.byType(PageView), const Offset(-400, 0));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.textContaining('Capture what God'), findsOneWidget);
  });

  testWidgets('onboarding survives a narrow screen at large text',
      (tester) async {
    await _pumpScreen(tester, const OnboardingScreen(),
        size: const Size(320, 640));
  });

  testWidgets('habits screen renders', (tester) async {
    await _pumpScreen(tester, const HabitsScreen());
    expect(tester.takeException(), isNull);
  });

  // These two were unreachable until the tab-shell lookup moved out of
  // build(): they threw before rendering a single pixel outside the shell.
  testWidgets('people list renders outside the tab shell', (tester) async {
    await _pumpScreen(
      tester,
      const PeopleListScreen(),
      overrides: [
        peopleStreamProvider.overrideWith((ref) => Stream.value(const [])),
      ],
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('promises list renders outside the tab shell', (tester) async {
    await _pumpScreen(
      tester,
      const PromisesListScreen(),
      overrides: [
        promisesStreamProvider.overrideWith((ref) => Stream.value(const [])),
      ],
    );
    expect(tester.takeException(), isNull);
  });
}
