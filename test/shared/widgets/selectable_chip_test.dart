// The chip behind four tag inputs and the Bible search filters. Its label is a
// name the user typed, so it has to survive one longer than the row is wide —
// before this, nothing in the chip could yield and a long tag ran 306px off a
// 320pt screen.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:notify/core/theme/app_theme.dart';
import 'package:notify/shared/widgets/selectable_chip.dart';

Future<void> pumpChips(WidgetTester tester, List<String> labels,
    {double width = 320, bool showDelete = false}) async {
  tester.view.physicalSize = Size(width, 640) * 3;
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light(),
    home: Scaffold(
      body: Wrap(
        children: [
          for (final l in labels)
            SelectableChip(
              label: l,
              isSelected: true,
              showDelete: showDelete,
              onTap: () {},
            ),
        ],
      ),
    ),
  ));
  await tester.pump();
}

void main() {
  testWidgets('a short label renders whole', (tester) async {
    await pumpChips(tester, ['faith']);

    expect(tester.takeException(), isNull);
    expect(find.text('faith'), findsOneWidget);
  });

  testWidgets('a label longer than the screen does not overflow',
      (tester) async {
    await pumpChips(tester, ['thanksgiving-and-praise-and-intercession-too']);

    expect(tester.takeException(), isNull);
  });

  testWidgets('several long labels together do not overflow', (tester) async {
    await pumpChips(tester, [
      'thanksgiving-and-praise-and-more',
      'intercession-for-the-nations',
    ]);

    expect(tester.takeException(), isNull);
  });

  testWidgets('the delete affordance still fits beside a long label',
      (tester) async {
    await pumpChips(tester, ['thanksgiving-and-praise-and-more'],
        showDelete: true);

    expect(tester.takeException(), isNull);
    expect(find.byIcon(Icons.close), findsOneWidget);
  });
}
