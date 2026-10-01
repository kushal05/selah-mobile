// TapTarget holds a control's touch area to the 44pt floor without changing
// how large the control is drawn.
//
// It used to take the child's drawn size as parameters and pad by the
// difference, which meant a control redrawn smaller with its constant left
// alone quietly lost part of its target. It measures the child now. These pin
// the floor on each axis, the untouched drawing, and above all that the target
// follows the child rather than a number someone has to remember to update.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:notify/core/theme/app_theme.dart';
import 'package:notify/shared/widgets/tap_target.dart';

const _floor = AppTheme.minTapTarget;

/// A plain box the size given, standing in for a drawn control.
Widget _box(double w, double h) =>
    SizedBox(key: const ValueKey('drawn'), width: w, height: h);

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  VoidCallback? onTap,
  Widget Function(Widget)? host,
}) {
  final target = TapTarget(onTap: onTap ?? () {}, child: child);
  return tester.pumpWidget(MaterialApp(
    home: Scaffold(body: (host ?? (w) => Center(child: w))(target)),
  ));
}

Size _target(WidgetTester t) => t.getSize(find.byType(TapTarget));
Size _drawn(WidgetTester t) => t.getSize(find.byKey(const ValueKey('drawn')));

void main() {
  testWidgets('a small square control gets the floor on both axes',
      (tester) async {
    await _pump(tester, _box(30, 30));

    expect(_target(tester), const Size(_floor, _floor));
    expect(_drawn(tester), const Size(30, 30),
        reason: 'the control itself must not grow');
  });

  testWidgets('a wide, short control is held only where it falls short',
      (tester) async {
    await _pump(tester, _box(128, 36));

    expect(_target(tester), const Size(128, _floor));
    expect(_drawn(tester), const Size(128, 36));
  });

  testWidgets('a control already past the floor is left as it is',
      (tester) async {
    await _pump(tester, _box(60, 60));

    expect(_target(tester), const Size(60, 60));
  });

  testWidgets('a control redrawn smaller still gets the whole target',
      (tester) async {
    // The case that retired the old parameters. There, shrinking the drawing
    // without updating its constant left the target short of 44 with nothing
    // on screen to show it. Here there is no constant to forget.
    await _pump(tester, _box(30, 30));
    expect(_target(tester), const Size(_floor, _floor));

    await _pump(tester, _box(20, 20));
    expect(_drawn(tester), const Size(20, 20));
    expect(_target(tester), const Size(_floor, _floor),
        reason: 'the target follows the drawing, not a number');
  });

  testWidgets('the control sits centred in its target', (tester) async {
    await _pump(tester, _box(30, 30));

    expect(
      tester.getCenter(find.byKey(const ValueKey('drawn'))),
      tester.getCenter(find.byType(TapTarget)),
    );
  });

  testWidgets('a tap in the margin around the control still fires',
      (tester) async {
    var taps = 0;
    await _pump(tester, _box(30, 30), onTap: () => taps++);

    final target = tester.getRect(find.byType(TapTarget));
    // The corner: inside the target, outside the 30pt drawing.
    await tester.tapAt(target.topLeft + const Offset(2, 2));
    expect(taps, 1);
  });

  // The three kinds of parent the app puts these in. A Center was where the
  // old pill blew up to 800x600; a Row is the notes filter bar; a Wrap is the
  // song filter dialog.
  for (final host in <String, Widget Function(Widget)>{
    'a Row': (w) => Row(mainAxisSize: MainAxisSize.min, children: [w]),
    'a Wrap': (w) => SizedBox(width: 300, child: Wrap(children: [w])),
  }.entries) {
    testWidgets('and it measures the same inside ${host.key}', (tester) async {
      await _pump(tester, _box(30, 30), host: host.value);

      expect(_target(tester), const Size(_floor, _floor));
      expect(_drawn(tester), const Size(30, 30));
    });
  }
}
