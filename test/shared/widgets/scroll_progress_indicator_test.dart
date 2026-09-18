// The quick actions row scrolls horizontally, and four tiles fill the width.
// Without a bar underneath, people read the row as complete and never find
// the three actions to the right of the fold.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:notify/core/theme/app_theme.dart';
import 'package:notify/shared/widgets/scroll_progress_indicator.dart';

void main() {
  late ScrollController controller;

  setUp(() => controller = ScrollController());
  tearDown(() => controller.dispose());

  /// A [viewport]-wide window onto [content] of tiles, with the bar beneath.
  Widget harness({required double viewport, required double content}) {
    return MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: viewport,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SingleChildScrollView(
                  controller: controller,
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(width: content, height: 40),
                ),
                ScrollProgressIndicator(controller: controller),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Where the thumb sits along the track, -1 (start) to 1 (end).
  double thumbX(WidgetTester tester) {
    final align = tester.widget<Align>(find.descendant(
      of: find.byType(ScrollProgressIndicator),
      matching: find.byType(Align),
    ));
    return (align.alignment as Alignment).x;
  }

  bool barDrawn(WidgetTester tester) => find
      .descendant(
        of: find.byType(ScrollProgressIndicator),
        matching: find.byType(Stack),
      )
      .evaluate()
      .isNotEmpty;

  testWidgets('draws a bar when the row runs off the edge', (tester) async {
    await tester.pumpWidget(harness(viewport: 200, content: 600));
    await tester.pump();
    expect(barDrawn(tester), isTrue);
  });

  testWidgets('draws nothing when the row already fits', (tester) async {
    await tester.pumpWidget(harness(viewport: 200, content: 120));
    await tester.pump();
    expect(barDrawn(tester), isFalse,
        reason: 'a bar that can never move claims there is more to see');
  });

  testWidgets('reserves its height either way, so nothing shifts',
      (tester) async {
    await tester.pumpWidget(harness(viewport: 200, content: 120));
    await tester.pump();
    expect(tester.getSize(find.byType(ScrollProgressIndicator)).height,
        ScrollProgressIndicator.reservedHeight);
  });

  testWidgets('the thumb tracks the finger as the row is dragged',
      (tester) async {
    await tester.pumpWidget(harness(viewport: 200, content: 600));
    await tester.pump();
    final atRest = thumbX(tester);
    expect(atRest, -1.0, reason: 'unscrolled, the thumb sits at the start');

    await tester.drag(
        find.byType(SingleChildScrollView), const Offset(-200, 0));
    await tester.pump();
    final dragged = thumbX(tester);
    expect(dragged, greaterThan(atRest));

    // All the way to the end lands the thumb against the right edge.
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pump();
    expect(thumbX(tester), 1.0);
    expect(thumbX(tester), greaterThan(dragged));
  });

  testWidgets('the thumb is narrower the more of the row is hidden',
      (tester) async {
    Future<double> thumbWidth(double content) async {
      await tester.pumpWidget(harness(viewport: 200, content: content));
      await tester.pump();
      return tester
          .getSize(find.descendant(
            of: find.byType(Align),
            matching: find.byType(Container),
          ))
          .width;
    }

    final shortRow = await thumbWidth(400);
    final longRow = await thumbWidth(2000);
    expect(longRow, lessThan(shortRow));
  });
}
