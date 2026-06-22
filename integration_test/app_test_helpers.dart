/// Shared helpers for integration tests.
///
/// Provides [pumpApp] which boots the real app with
/// `IntegrationTestWidgetsFlutterBinding` already initialised.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Initialise the integration-test binding once per process.
/// Call this at the top of every test file's `main()`.
IntegrationTestWidgetsFlutterBinding ensureBinding() {
  return IntegrationTestWidgetsFlutterBinding.ensureInitialized();
}

// ──────────────────────────────────────────────
// Boot helpers
// ──────────────────────────────────────────────

/// Launch the app, pump past the splash screen's [Future.delayed(1800ms)],
/// tap "Skip (Testing)" on the login screen, and wait for the home screen.
///
/// Call this at the start of every non-auth test instead of manually
/// calling `app.main()` + `pumpAndSettle()`.
///
/// [appMain] should be `app.main` (imported from `package:notify/main.dart`).
Future<void> bootAppAndSkipLogin(
  WidgetTester tester,
  void Function() appMain,
) async {
  appMain();

  // app.main() is async — poll until the widget tree is built.
  for (int i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (find.byType(MaterialApp).evaluate().isNotEmpty) break;
  }

  // Splash uses Future.delayed(1800ms). pumpAndSettle does not advance real
  // timers, so explicitly pump past it, then pump a few frames for navigation.
  await tester.pump(const Duration(seconds: 2));
  // NOTE: Do NOT use pumpAndSettle() here — the sync service and other
  // background timers keep scheduling frames indefinitely, causing a
  // 10-minute timeout. Use bounded pumps instead.
  await _pumpFrames(tester);

  // If we landed on the login screen, tap "Skip (Testing)" to bypass auth.
  final skipButton = find.widgetWithText(TextButton, 'Skip (Testing)');
  if (await waitFor(tester, skipButton, timeout: const Duration(seconds: 10))) {
    await tester.tap(skipButton);
    await _pumpFrames(tester);
  }

  // Wait for the login entrance animation (2s) + the Skip handler navigation.
  await tester.pump(const Duration(seconds: 2));
  await _pumpFrames(tester);

  // Wait for home screen to load (NavigationBar or BottomNavigationBar).
  await waitFor(tester, find.byType(NavigationBar),
      timeout: const Duration(seconds: 15));
  await _pumpFrames(tester);
}

/// Pump a bounded number of frames to let navigation and animations progress
/// without waiting for all timers to settle (which never happens when the
/// sync service is running).
Future<void> _pumpFrames(WidgetTester tester, {int frames = 20}) async {
  for (int i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Navigate to a bottom navigation tab by its label text.
///
/// Finds the [NavigationDestination] with the given [label] and taps it.
/// This is more reliable than icon-based finders because [NavigationBar]
/// internally wraps icons in animated builders that may not match
/// [find.byIcon].
Future<void> tapTab(WidgetTester tester, String label) async {
  final destination = find.widgetWithText(NavigationDestination, label);
  if (destination.evaluate().isNotEmpty) {
    await tester.tap(destination.first);
    await settle(tester);
    return;
  }
  // Fallback: tap the label text directly (last match is usually the nav label)
  final text = find.text(label);
  if (text.evaluate().isNotEmpty) {
    await tester.tap(text.last);
    await settle(tester);
  }
}

// ──────────────────────────────────────────────
// Finders (semantic)
// ──────────────────────────────────────────────

/// Find a widget whose text matches [text] (exact).
Finder findText(String text) => find.text(text);

/// Find the first [ElevatedButton] or [TextButton] whose descendant text
/// matches [label].
Finder findButton(String label) => find.widgetWithText(ElevatedButton, label);

Finder findTextButton(String label) =>
    find.widgetWithText(TextButton, label);

/// Find any widget by [Key].
Finder findByKey(Key key) => find.byKey(key);

/// Find by widget type.
Finder findByType(Type type) => find.byType(type);

// ──────────────────────────────────────────────
// Actions
// ──────────────────────────────────────────────

/// Tap the first widget matched by [finder], then pump frames.
///
/// Uses a bounded pump loop instead of [pumpAndSettle] because the sync
/// service keeps scheduling frames indefinitely.
Future<void> tapAndSettle(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await settle(tester);
}

/// Bounded alternative to [WidgetTester.pumpAndSettle].
///
/// The sync service and other background timers schedule frames forever,
/// so [pumpAndSettle] times out after 10 minutes. This pumps a fixed
/// number of frames (default 20 × 100ms = 2s) which is enough for
/// navigation and animations.
Future<void> settle(WidgetTester tester, {Duration duration = const Duration(milliseconds: 500)}) async {
  final frames = duration.inMilliseconds ~/ 100;
  for (int i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Enter [text] into the [TextField] / [TextFormField] matched by [finder].
Future<void> enterText(
    WidgetTester tester, Finder finder, String text) async {
  await tester.enterText(finder, text);
  await settle(tester);
}

/// Scroll down inside [scrollable] until [item] is visible.
Future<void> scrollUntilVisible(
  WidgetTester tester,
  Finder item, {
  Finder? scrollable,
  double delta = 300,
}) async {
  await tester.scrollUntilVisible(
    item,
    delta,
    scrollable: scrollable ?? find.byType(Scrollable).first,
  );
}

/// Wait for a finder to appear within [timeout].
Future<bool> waitFor(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 200));
    if (finder.evaluate().isNotEmpty) return true;
  }
  return false;
}

/// Swipe a widget to the left (for swipe actions).
Future<void> swipeLeft(WidgetTester tester, Finder finder) async {
  await tester.drag(finder, const Offset(-300, 0));
  await settle(tester);
}

/// Swipe a widget to the right (for swipe actions).
Future<void> swipeRight(WidgetTester tester, Finder finder) async {
  await tester.drag(finder, const Offset(300, 0));
  await settle(tester);
}

/// Long-press a widget and settle.
Future<void> longPress(WidgetTester tester, Finder finder) async {
  await tester.longPress(finder);
  await settle(tester);
}

/// Safe alternative to [WidgetTester.pageBack] that doesn't throw if no
/// back button is found. Returns true if a back navigation was performed.
Future<bool> safePageBack(WidgetTester tester) async {
  final backButton = find.byIcon(Icons.arrow_back);
  final backButtonIos = find.byIcon(Icons.arrow_back_ios);
  final closeButton = find.byIcon(Icons.close);
  if (backButton.evaluate().isNotEmpty) {
    await tester.tap(backButton.first);
    await settle(tester);
    return true;
  } else if (backButtonIos.evaluate().isNotEmpty) {
    await tester.tap(backButtonIos.first);
    await settle(tester);
    return true;
  } else if (closeButton.evaluate().isNotEmpty) {
    await tester.tap(closeButton.first);
    await settle(tester);
    return true;
  }
  return false;
}

// ──────────────────────────────────────────────
// Assertions
// ──────────────────────────────────────────────

/// Assert a finder matches at least one widget.
void expectVisible(Finder finder) {
  expect(finder, findsAtLeastNWidgets(1));
}

/// Assert a finder matches zero widgets.
void expectNotVisible(Finder finder) {
  expect(finder, findsNothing);
}

/// Assert a finder matches exactly [n] widgets.
void expectCount(Finder finder, int n) {
  expect(finder, findsNWidgets(n));
}
