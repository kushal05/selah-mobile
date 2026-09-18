// The folder lays seven actions out like a home-screen folder.
//
// It used to place four 80pt tiles in a 330pt panel with spaceBetween, which
// left 2.7pt between them — they read as one block — while the short second
// row used start alignment, so the same column sat in two different places.
// On a 360pt phone the four fixed tiles did not fit at all.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:notify/core/theme/app_theme.dart';
import 'package:notify/l10n/app_localizations.dart';
import 'package:notify/features/home/presentation/widgets/quick_actions_row.dart';
import 'package:notify/shared/widgets/buttons/quick_action_button.dart';

final _actions = List.generate(
  7,
  (i) => QuickActionSpec(
    icon: Icons.add,
    // "Go" is deliberately short. The test font makes every glyph a square,
    // so a realistic label like "Songs" wraps to two lines here even where it
    // would not on device — and then every tile is the same height whatever
    // the layout does, and the ragged-bottom assertion below can never fail.
    label: const [
      'New Prayer', 'New Note', 'Read Bible', 'Search',
      'New Promise', 'Go', 'Add person',
    ][i],
    color: AppTheme.brandBlue,
    onTap: (_) {},
  ),
);

Future<void> openFolder(
  WidgetTester tester, {
  required double width,
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = Size(width, 874) * 3;
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light(),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    builder: (context, child) => MediaQuery.withClampedTextScaling(
      minScaleFactor: textScale,
      maxScaleFactor: textScale,
      child: child!,
    ),
    home: Builder(
      builder: (c) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () => showQuickActionsFolder(c, _actions),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

List<Rect> tileRects(WidgetTester tester) {
  final tiles = find.byType(QuickActionButton);
  return List.generate(
      tiles.evaluate().length, (i) => tester.getRect(tiles.at(i)));
}

void main() {
  testWidgets('the tiles are held apart, not butted together',
      (tester) async {
    await openFolder(tester, width: 402);
    final r = tileRects(tester);

    // The first row is full, so its three gaps are the grid's gutter.
    final gaps = [for (var i = 1; i < 4; i++) r[i].left - r[i - 1].right];
    for (final gap in gaps) {
      expect(gap, greaterThanOrEqualTo(8.0),
          reason: 'tiles 2.7pt apart read as one block');
    }
    expect(gaps.toSet().length, 1, reason: 'one gutter, evenly applied');
  });

  testWidgets('the second row sits on the same columns as the first',
      (tester) async {
    await openFolder(tester, width: 402);
    final r = tileRects(tester);
    for (var c = 0; c < 3; c++) {
      expect(r[4 + c].left, moreOrLessEquals(r[c].left, epsilon: 0.5),
          reason: 'column $c is in two different places');
    }
  });

  testWidgets('tiles in a row share a height, so the bottoms line up',
      (tester) async {
    await openFolder(tester, width: 402);
    final r = tileRects(tester);
    // Row two is the one that showed it: a one-line "Songs" between two
    // two-line labels left a notch in the bottom edge.
    for (var i = 5; i < 7; i++) {
      expect(r[i].bottom, moreOrLessEquals(r[4].bottom, epsilon: 0.5),
          reason: 'tile $i ends at a different height from its row');
      expect(r[i].top, moreOrLessEquals(r[4].top, epsilon: 0.5));
    }
    for (var i = 1; i < 4; i++) {
      expect(r[i].bottom, moreOrLessEquals(r[0].bottom, epsilon: 0.5));
    }
  });

  testWidgets('drops a column rather than overflow a narrow phone',
      (tester) async {
    await openFolder(tester, width: 320);
    expect(tester.takeException(), isNull);

    final r = tileRects(tester);
    // Three per row: the fourth tile starts a new one.
    expect(r[3].top, greaterThan(r[0].bottom));
    expect(r[3].left, moreOrLessEquals(r[0].left, epsilon: 0.5));
  });

  testWidgets('fits within the panel at every width it supports',
      (tester) async {
    for (final width in [320.0, 360.0, 402.0, 430.0]) {
      await openFolder(tester, width: width);
      expect(tester.takeException(), isNull, reason: 'overflowed at $width');
      for (final rect in tileRects(tester)) {
        expect(rect.left, greaterThanOrEqualTo(0.0));
        expect(rect.right, lessThanOrEqualTo(width),
            reason: 'a tile ran off the $width screen');
      }
    }
  });

  testWidgets('holds together at 200% text', (tester) async {
    await openFolder(tester, width: 402, textScale: 2.0);
    expect(tester.takeException(), isNull);
  });
}
