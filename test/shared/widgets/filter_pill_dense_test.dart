// A dense pill is smaller to look at without being smaller to hit.
//
// `dense` used to change only type, icon and padding — the chip still painted
// at the full 44 tap target, so it did not actually look any shorter. Pulling
// the painted height down to 36 is the easy half; the half worth a test is that
// the 44 target survives it, because nothing about the appearance would reveal
// a lost 8 points of hit area.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:notify/core/theme/app_theme.dart';
import 'package:notify/shared/widgets/filter_pill.dart';

/// The one box inside the pill that carries the border and fill — what the user
/// sees, as opposed to what answers a tap.
Finder _painted(Finder pill) => find.descendant(
  of: pill,
  matching: find.byWidgetPredicate(
    (w) =>
        w is Container &&
        w.decoration is BoxDecoration &&
        (w.decoration! as BoxDecoration).border != null,
  ),
);

Future<void> _pump(
  WidgetTester tester, {
  required bool dense,
  VoidCallback? onTap,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        // A Column of a Row, because that is the shape of the real filter bar,
        // and the shape is load-bearing here. The pill's painted box centres its
        // content, and centring expands to fill whatever bounded height it is
        // offered — drop the pill into a bare Center and it measures 800x600
        // however dense it claims to be. A Column hands its children unbounded
        // height, so the box shrink-wraps as it does on the screen.
        body: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                FilterPill(
                  icon: Icons.label_outlined,
                  label: 'Tags',
                  selected: false,
                  dense: dense,
                  onTap: onTap ?? () {},
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('a dense pill is painted at 36', (tester) async {
    await _pump(tester, dense: true);

    expect(
      tester.getSize(_painted(find.byType(FilterPill))).height,
      FilterPill.densePaintHeight,
    );
  });

  testWidgets('but still occupies the full 44 tap target', (tester) async {
    await _pump(tester, dense: true);

    expect(
      tester.getSize(find.byType(FilterPill)).height,
      AppTheme.minTapTarget,
      reason: 'shrinking the paint must not shrink the target',
    );
  });

  testWidgets('and a tap in the strip above the pill still fires', (
    tester,
  ) async {
    // The points between the top of the target and the top of the chip. This is
    // the whole point of the wrapper: without it this tap lands on nothing.
    var taps = 0;
    await _pump(tester, dense: true, onTap: () => taps++);

    final pill = find.byType(FilterPill);
    final target = tester.getRect(pill);
    final painted = tester.getRect(_painted(pill));
    final strip = painted.top - target.top;
    expect(strip, greaterThan(0), reason: 'there is no strip to test');

    await tester.tapAt(Offset(target.center.dx, target.top + strip / 2));
    await tester.pump();

    expect(taps, 1);
  });

  testWidgets('the pill itself still handles its own taps', (tester) async {
    // The wrapper sits above the InkWell in the tree, so the obvious way to get
    // this wrong is a tap on the chip firing both of them.
    var taps = 0;
    await _pump(tester, dense: true, onTap: () => taps++);

    await tester.tap(find.byType(FilterPill));
    await tester.pump();

    expect(taps, 1, reason: 'a tap on the chip must fire exactly once');
  });

  testWidgets('a dense pill exposes one button, not two', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, dense: true);

    expect(
      tester.getSemantics(
        find.descendant(
          of: find.byType(FilterPill),
          matching: find.byType(Semantics),
        ).first,
      ),
      isSemantics(isButton: true, label: 'Tags'),
      reason: 'the chip must still be a button to a screen reader',
    );
    // The wrapper would otherwise add a second tappable node over the first.
    expect(
      find.descendant(
        of: find.byType(FilterPill),
        matching: find.byWidgetPredicate(
          (w) => w is GestureDetector && !w.excludeFromSemantics,
        ),
      ),
      findsNothing,
    );
    handle.dispose();
  });

  testWidgets('a normal pill is unchanged — painted and tapped at 44', (
    tester,
  ) async {
    // Four other screens use the non-dense pill; this change must not reach
    // them.
    await _pump(tester, dense: false);

    expect(
      tester.getSize(_painted(find.byType(FilterPill))).height,
      AppTheme.minTapTarget,
    );
    // Equal to the painted height, which is the assertion: no wrapper, no
    // strip, nothing between the chip's edge and its target.
    expect(
      tester.getSize(find.byType(FilterPill)).height,
      AppTheme.minTapTarget,
    );
  });

  // ── width ─────────────────────────────────────────────────────────────────
  // The pill used `alignment:` to centre its label, which centres by expanding:
  // in any parent that allowed more width than the label needed, the pill took
  // all of it. A Wrap allows a full row, so the song filter dialog drew one key
  // per line. These measure the three kinds of parent the app actually uses.

  Widget host(Widget child, {double width = 300}) => MaterialApp(
    home: Scaffold(
      body: Center(child: SizedBox(width: width, child: child)),
    ),
  );

  FilterPill pill(String label, {bool dense = true}) => FilterPill(
    label: label,
    selected: false,
    dense: dense,
    onTap: () {},
  );

  testWidgets('in a Wrap, a pill is as wide as its label', (tester) async {
    await tester.pumpWidget(host(Wrap(spacing: 8, children: [
      pill('C'), pill('C#'), pill('D'),
    ])));

    final c = tester.getRect(find.widgetWithText(FilterPill, 'C'));
    expect(c.width, lessThan(80), reason: 'a one-letter key, not a full row');

    // And so they share a line, which is the point of a Wrap.
    final d = tester.getRect(find.widgetWithText(FilterPill, 'D'));
    expect(d.top, c.top, reason: 'three short keys should fit on one line');
  });

  testWidgets('in an Expanded, it still fills its share', (tester) async {
    // Prayers lays its three filters out as equal thirds, on purpose. Tight
    // constraints override the shrink-wrap, so that must not change.
    await tester.pumpWidget(host(Row(children: [
      Expanded(child: pill('All', dense: false)),
      const SizedBox(width: 10),
      Expanded(child: pill('Active', dense: false)),
      const SizedBox(width: 10),
      Expanded(child: pill('Answered', dense: false)),
    ])));

    final widths = ['All', 'Active', 'Answered']
        .map((l) => tester.getSize(find.widgetWithText(FilterPill, l)).width)
        .toList();
    expect(widths.toSet(), hasLength(1),
        reason: 'equal thirds whatever the label length');
    expect(widths.first, closeTo((300 - 20) / 3, 0.5));
  });

  testWidgets('and given a whole screen, it stays pill-sized', (tester) async {
    // The case the harness above has to steer around: straight into a Center,
    // the old pill measured 800x600. It should simply be a pill.
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Center(child: pill('Tags', dense: false))),
    ));

    final size = tester.getSize(find.byType(FilterPill));
    expect(size.height, AppTheme.minTapTarget);
    expect(size.width, lessThan(120));
  });
}
