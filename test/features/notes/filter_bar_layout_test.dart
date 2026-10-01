// The filter bar spans the screen, and its pills are shorter than its height.
//
// The bar draws a hairline along its bottom edge as the divider between the
// controls and the list. It sat inside a Column that centres its children
// rather than stretching them, so the bar shrank to the width of the pills and
// the rule stopped short on both sides — a short line floating in the middle of
// the screen. Nothing about that is visible to a test that only looks for the
// widgets, so this measures.
//
// Measured against the real screen rather than a replica: the defect was the
// relationship between the bar and the Column above it, which a replica would
// reproduce only if it already knew the answer.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:notify/core/sync/providers/sync_providers.dart';
import 'package:notify/core/theme/app_theme.dart';
import 'package:notify/l10n/l10n.dart';
import 'package:notify/features/notes/presentation/providers/database_provider.dart';
import 'package:notify/features/notes/presentation/providers/notes_home_ui_state.dart';
import 'package:notify/features/notes/presentation/screens/notes_home_screen.dart';
import 'package:notify/shared/widgets/filter_pill.dart';
import 'package:notify/shared/widgets/tap_target.dart';

/// The bar itself: the one box around the pills carrying a bottom-only border.
/// `Border.all` on the pills has a top side as well, which is what separates
/// them from this.
final _bar = find.ancestor(
  of: find.byType(FilterPill).first,
  matching: find.byWidgetPredicate((w) {
    if (w is! Container) return false;
    final d = w.decoration;
    if (d is! BoxDecoration) return false;
    final b = d.border;
    return b is Border && b.top == BorderSide.none && b.bottom.width == 1;
  }),
);

/// The Filter toggle, found by its accessible name rather than its glyph.
final _toggle = find.byWidgetPredicate(
  (w) => w is Semantics && w.properties.label == 'Show or hide filters',
);

/// Clearing every filter at once — only rendered when there is something to
/// clear, which is why it needs its own pump.
final _clear = find.byWidgetPredicate(
  (w) => w is Semantics && w.properties.label == 'Clear filters',
);

Future<void> _pumpWithFiltersOpen(
  WidgetTester tester, {
  bool withActiveFilter = false,
  double? width,
}) async {
  if (width != null) {
    // Six pills need about 1000pt to lay out side by side. Centring is only a
    // question when they fit, so the tests that measure it say so by asking for
    // a viewport that holds them, rather than quietly depending on the default
    // 800 — which they did until the smart collections moved in here and the
    // bar started scrolling.
    tester.view.physicalSize = Size(width * 3, 1800);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();

  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      notesStreamProvider.overrideWith((ref) => Stream.value(const [])),
      noteFoldersStreamProvider.overrideWith((ref) => Stream.value(const [])),
      peopleStreamProvider.overrideWith((ref) => Stream.value(const [])),
      tagsStreamProvider.overrideWith((ref) => Stream.value(const [])),
    ],
  );
  addTearDown(container.dispose);

  // The bar is hidden by default now, so open it the way the button does.
  final ui = container.read(notesHomeUiProvider.notifier)
    ..setFilterBarVisible(true);
  if (withActiveFilter) ui.setTagFilter({'tag-1'});

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const NotesHomeScreen(),
      ),
    ),
  );
  // Twice, and the second one matters: a single pump advances one frame, which
  // is enough for the people and folder streams but not for the tags stream.
  // With one pump the Tags pill is simply absent and the first pill found is
  // "Preacher" — every assertion here still passed, measuring two pills instead
  // of three.
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump();
  assert(
    tester.widgetList(find.byType(FilterPill)).length == 6,
    'the bar should offer three smart collections and three filters',
  );
}

void main() {
  testWidgets('the filter bar fills the width of the screen', (tester) async {
    await _pumpWithFiltersOpen(tester);

    expect(_bar, findsOneWidget, reason: 'the filter bar is not on screen');
    expect(
      tester.getSize(_bar).width,
      tester.getSize(find.byType(MaterialApp)).width,
      reason: 'the bottom rule must reach both edges, not float in the middle',
    );
  });

  testWidgets('its bottom rule starts at the left edge', (tester) async {
    // Width alone would be satisfied by a bar the right size in the wrong
    // place.
    await _pumpWithFiltersOpen(tester);

    expect(tester.getTopLeft(_bar).dx, 0);
  });

  testWidgets('the pills sit centred in the bar', (tester) async {
    // Making the bar full width moved the pills from the middle of the screen
    // to its left edge, because a Row inside a horizontal scroll view has no
    // width to align within. This is the assertion that the floor restoring it
    // is actually in place.
    await _pumpWithFiltersOpen(tester, width: 1400);

    final pills = find.byType(FilterPill);
    final first = tester.getRect(pills.first);
    final last = tester.getRect(pills.last);

    expect(
      (first.left + last.right) / 2,
      closeTo(tester.getRect(_bar).center.dx, 0.5),
      reason: 'the group of pills must be centred on the bar',
    );
  });

  testWidgets('and the gaps either side of them are equal', (tester) async {
    // The same fact from the other direction: a group whose centre is right can
    // still have been reached by clipping one end.
    await _pumpWithFiltersOpen(tester, width: 1400);

    final pills = find.byType(FilterPill);
    final bar = tester.getRect(_bar);
    final leftGap = tester.getRect(pills.first).left - bar.left;
    final rightGap = bar.right - tester.getRect(pills.last).right;

    expect(leftGap, greaterThan(0), reason: 'the pills are flush left again');
    expect(leftGap, closeTo(rightGap, 0.5));
  });

  testWidgets('the width it centres in is a floor, not a fixed size', (
    tester,
  ) async {
    // Centring needs the Row to be given a width, and the cheap way to give it
    // one is to fix it — which would clip the pills on a narrow phone instead of
    // letting the bar scroll. A floor with an unbounded ceiling is what makes
    // both cases work, so that is what gets asserted.
    //
    // Measured here rather than on a deliberately narrow viewport: this screen
    // already overflows elsewhere below about 300pt (folder_section.dart:215 and
    // the section header), so a narrow pump fails for reasons that have nothing
    // to do with the filter bar.
    await _pumpWithFiltersOpen(tester);

    // Specifically the one between the scroll view and the pills. Taking the
    // first ConstrainedBox under the bar instead finds the one Container builds
    // for its own `width: double.infinity`, which is unbounded whatever the
    // floor does — this assertion passed against a deliberately fixed width
    // until the finder was narrowed.
    final floor = find.ancestor(
      of: find.byType(FilterPill).first,
      matching: find.descendant(
        of: find.descendant(
          of: _bar,
          matching: find.byType(SingleChildScrollView),
        ),
        matching: find.byType(ConstrainedBox),
      ),
    );
    expect(floor, findsOneWidget, reason: 'the floor is not where it was');

    final box = tester.widget<ConstrainedBox>(floor);
    expect(box.constraints.minWidth, greaterThan(0),
        reason: 'without a floor there is nothing to centre within');
    expect(box.constraints.maxWidth, double.infinity,
        reason: 'a ceiling here would clip the pills instead of scrolling them');
  });

  testWidgets('and at phone width the pills scroll rather than being cut off', (
    tester,
  ) async {
    // Six pills come to roughly 1000pt, so on any real phone the bar overflows.
    // This is the case the minWidth floor has to not break: a fixed width would
    // clip the last pills with no way to reach them.
    await _pumpWithFiltersOpen(tester);

    final scroller = find.descendant(
      of: _bar,
      matching: find.byType(Scrollable),
    );
    expect(scroller, findsOneWidget);

    final position = tester.state<ScrollableState>(scroller).position;
    expect(position.maxScrollExtent, greaterThan(0),
        reason: 'the pills overflow, so there must be somewhere to scroll to');

    // And the far end is reachable.
    await tester.drag(scroller, const Offset(-400, 0));
    await tester.pumpAndSettle();
    expect(position.pixels, greaterThan(0));
  });

  testWidgets('the pills inside it are drawn shorter than their target', (
    tester,
  ) async {
    // Pins the wiring, not the widget: `dense: true` has to actually reach the
    // pills. The widget's own behaviour is covered in
    // test/shared/widgets/filter_pill_dense_test.dart.
    await _pumpWithFiltersOpen(tester);

    final pill = find.byType(FilterPill).first;
    final painted = find.descendant(
      of: pill,
      matching: find.byWidgetPredicate(
        (w) =>
            w is Container &&
            w.decoration is BoxDecoration &&
            (w.decoration! as BoxDecoration).border != null,
      ),
    );

    expect(tester.getSize(painted).height, FilterPill.densePaintHeight);
    expect(
      tester.getSize(pill).height,
      AppTheme.minTapTarget,
      reason: 'a shorter chip must still be a 44pt target',
    );
  });

  testWidgets('the Filter toggle answers a full 44pt touch', (tester) async {
    // It replaced an 18pt bare icon, and at first replaced it with a 36pt one:
    // better, but still under the floor. The chip beside it was already held to
    // 44 by the same wrapper, so the two disagreed about what a target is.
    await _pumpWithFiltersOpen(tester);

    expect(_toggle, findsOneWidget);
    expect(
      tester.getSize(find.ancestor(of: _toggle, matching: find.byType(TapTarget))).height,
      AppTheme.minTapTarget,
    );
  });

  testWidgets('but is still drawn at the height of the chips it opens', (
    tester,
  ) async {
    // The point of the wrapper is that nothing looks different. If the toggle
    // had simply grown to 44 it would no longer sit level with the dense chips.
    await _pumpWithFiltersOpen(tester);

    expect(
      tester.getSize(_toggle).height,
      FilterPill.densePaintHeight,
      reason: 'the painted button must not have grown',
    );
  });

  testWidgets('clearing filters answers a full 44pt touch, both ways', (
    tester,
  ) async {
    // 30x30 before: a 16pt glyph in 6pt of padding. It is the only destructive
    // control in the bar and it was the smallest thing to hit in it.
    await _pumpWithFiltersOpen(tester, withActiveFilter: true, width: 1400);

    expect(_clear, findsOneWidget, reason: 'no clear button to measure');
    final target =
        find.ancestor(of: _clear, matching: find.byType(TapTarget));

    expect(tester.getSize(target).height, AppTheme.minTapTarget);
    expect(tester.getSize(target).width, AppTheme.minTapTarget,
        reason: 'a square button falls short on both axes, not just height');
  });

  testWidgets('and is still drawn at its original size', (tester) async {
    await _pumpWithFiltersOpen(tester, withActiveFilter: true, width: 1400);

    expect(tester.getSize(_clear).height, 30);
    expect(tester.getSize(_clear).width, 30);
  });

  testWidgets('and still clears when tapped in the new margin', (tester) async {
    await _pumpWithFiltersOpen(tester, withActiveFilter: true, width: 1400);
    final target = find.ancestor(of: _clear, matching: find.byType(TapTarget));
    final outer = tester.getRect(target);
    final inner = tester.getRect(_clear);

    // A near miss, in the corner that used to be dead space.
    await tester.tapAt(Offset(outer.left + 2, inner.top - 2));
    await tester.pump();

    expect(_clear, findsNothing,
        reason: 'the filter should be gone, so the button should be too');
  });
}
