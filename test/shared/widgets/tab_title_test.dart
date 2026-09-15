// Tab headings sit at the same size and the same place on every tab.
//
// Two things made them drift, and neither was visible to any gate:
//
//   1. Flutter centres an AppBar title on iOS when the bar has fewer than
//      two actions. Prayers had one action and sat centred while Notes
//      (three) and Promises (two) sat left — so adding or removing a single
//      icon button silently moved a heading.
//   2. Every tab wrote titleLarge.copyWith(...) inline except the people
//      directory, which wrote a plain Text(...). That falls back to
//      appBarTheme.titleTextStyle at 18 against everyone else's 28.
//
// Both were reported by a person looking at two screens side by side.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:notify/core/theme/app_theme.dart';
import 'package:notify/shared/widgets/tab_title.dart';

Future<void> _pumpBar(
  WidgetTester tester, {
  required int actionCount,
  required ThemeData theme,
}) async {
  await tester.pumpWidget(MaterialApp(
    theme: theme,
    home: Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const TabTitle('Prayers'),
        actions: List.generate(
          actionCount,
          (_) => IconButton(icon: const Icon(Icons.search), onPressed: () {}),
        ),
      ),
    ),
  ));
}

void main() {
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    // One action is the case that used to centre on iOS.
    for (final actions in [1, 2, 3]) {
      testWidgets('title is left-aligned on $platform with $actions action(s)',
          (tester) async {
        await _pumpBar(tester,
            actionCount: actions,
            theme: AppTheme.light().copyWith(platform: platform));

        final title = tester.getTopLeft(find.text('Prayers')).dx;
        final screen = tester.getSize(find.byType(Scaffold)).width;
        expect(title, lessThan(screen / 4),
            reason: 'a centred title would start near the middle of the bar');
      });
    }
  }

  testWidgets('TabTitle uses titleLarge, not the 18pt app bar default',
      (tester) async {
    await _pumpBar(tester, actionCount: 1, theme: AppTheme.light());

    final rendered = tester.widget<Text>(find.text('Prayers'));
    final expected = AppTheme.light().textTheme.titleLarge!.fontSize;
    expect(rendered.style?.fontSize, expected);
    expect(expected, 28, reason: 'the size every other tab heading renders at');
  });

  testWidgets('TabTitle follows the theme into dark mode', (tester) async {
    await _pumpBar(tester, actionCount: 1, theme: AppTheme.dark());
    final rendered = tester.widget<Text>(find.text('Prayers'));
    expect(rendered.style?.color, AppTheme.dark().colorScheme.onSurface);
  });
}
