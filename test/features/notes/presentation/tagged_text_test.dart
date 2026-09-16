// A #tag must look the same when you are reading a note as when you are
// writing it. The detail screen renders blocks as plain text, so before this
// a tag styled in the editor was unstyled the moment you left it.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:notify/core/theme/app_theme.dart';
import 'package:notify/features/notes/presentation/widgets/tagged_text.dart';

List<(String, TextStyle?)> runs(WidgetTester tester) {
  final out = <(String, TextStyle?)>[];
  void walk(InlineSpan s) {
    if (s is TextSpan) {
      if (s.text != null && s.text!.isNotEmpty) out.add((s.text!, s.style));
      for (final c in s.children ?? const <InlineSpan>[]) {
        walk(c);
      }
    }
  }

  for (final t in tester.widgetList<Text>(find.byType(Text))) {
    if (t.textSpan != null) walk(t.textSpan!);
    if (t.data != null && t.data!.isNotEmpty) out.add((t.data!, t.style));
  }
  return out;
}

Future<void> pump(WidgetTester tester, String text,
    {Brightness brightness = Brightness.light}) async {
  await tester.pumpWidget(MaterialApp(
    key: ValueKey(brightness),
    theme: brightness == Brightness.dark ? AppTheme.dark() : AppTheme.light(),
    home: Scaffold(body: TaggedText(text)),
  ));
  await tester.pump();
}

void main() {
  testWidgets('a #tag is tinted when reading', (tester) async {
    await pump(tester, 'trusting in #faith today');

    final tag = runs(tester).firstWhere((r) => r.$1 == '#faith');
    expect(tag.$2?.backgroundColor, isNotNull);
  });

  testWidgets('every character survives', (tester) async {
    await pump(tester, 'a #faith. b #grace!');

    expect(runs(tester).map((r) => r.$1).join(), 'a #faith. b #grace!');
  });

  testWidgets('only the tag is tinted', (tester) async {
    await pump(tester, 'a #faith. b');

    final tinted =
        runs(tester).where((r) => r.$2?.backgroundColor != null).map((r) => r.$1);
    expect(tinted, ['#faith']);
  });

  testWidgets('plain text renders as a plain Text', (tester) async {
    await pump(tester, 'no tags here');

    expect(runs(tester).where((r) => r.$2?.backgroundColor != null), isEmpty);
    expect(find.text('no tags here'), findsOneWidget);
  });

  testWidgets('the ink follows the theme', (tester) async {
    await pump(tester, '#faith');
    final light =
        runs(tester).firstWhere((r) => r.$1 == '#faith').$2?.color;

    await pump(tester, '#faith', brightness: Brightness.dark);
    final dark = runs(tester).firstWhere((r) => r.$1 == '#faith').$2?.color;

    expect(light, isNot(dark));
  });

  testWidgets('it matches what the editor paints', (tester) async {
    // The editor's controller delegates to inlineTagStyle; if these ever
    // diverge a note would look different depending on whether you are
    // editing it.
    await pump(tester, '#faith');
    final rendered = runs(tester).firstWhere((r) => r.$1 == '#faith').$2;
    final expected =
        inlineTagStyle(const TextStyle(), Brightness.light);

    expect(rendered?.backgroundColor, expected.backgroundColor);
    expect(rendered?.color, expected.color);
  });
}
