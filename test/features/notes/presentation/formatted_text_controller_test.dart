// This controller paints the note editor's text. Bold/italic/underline runs
// went through it before inline #tags did, so these pin that behaviour first —
// the tag tint must be added on top of formatting, not instead of it.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notify/core/theme/app_theme.dart';
import 'package:notify/features/notes/domain/models/text_span_format.dart';
import 'package:notify/features/notes/presentation/widgets/editor/formatted_text_controller.dart';

/// Flattens the span tree into (text, style) pairs, in order.
List<(String, TextStyle?)> runs(TextSpan span) {
  final out = <(String, TextStyle?)>[];
  void walk(InlineSpan s) {
    if (s is TextSpan) {
      if (s.text != null && s.text!.isNotEmpty) out.add((s.text!, s.style));
      for (final c in s.children ?? const <InlineSpan>[]) {
        walk(c);
      }
    }
  }

  walk(span);
  return out;
}

/// Builds the span against a real, pumped theme.
///
/// The context is taken from the tree *after* the pump rather than captured
/// inside a Builder's build callback: doing it during the build read a stale
/// theme on the second pump, so a dark-mode assertion quietly compared light
/// against light.
Future<TextSpan> build(
  WidgetTester tester,
  FormattedTextEditingController controller, {
  Brightness brightness = Brightness.light,
}) async {
  // Keyed by brightness so a second pump builds a fresh tree. Without it the
  // identical const subtree was reused and the new theme never reached the
  // leaf — a dark-mode assertion then compared light against light and passed
  // for the wrong reason.
  await tester.pumpWidget(MaterialApp(
    key: ValueKey(brightness),
    theme: brightness == Brightness.dark ? AppTheme.dark() : AppTheme.light(),
    home: const SizedBox(),
  ));
  return controller.buildTextSpan(
    context: tester.element(find.byType(SizedBox)),
    style: const TextStyle(fontSize: 16),
    withComposing: false,
  );
}

void main() {
  testWidgets('plain text with no formats is one run', (tester) async {
    final c = FormattedTextEditingController(text: 'hello world');
    final span = await build(tester, c);

    expect(runs(span).map((r) => r.$1).join(), 'hello world');
  });

  testWidgets('a bold range splits the text into three runs', (tester) async {
    final c = FormattedTextEditingController(text: 'a bold b')
      ..updateFormats([const TextSpanFormat(start: 2, end: 6, isBold: true)]);
    final span = await build(tester, c);
    final r = runs(span);

    expect(r.map((x) => x.$1).join(), 'a bold b');
    final boldRun = r.firstWhere((x) => x.$1 == 'bold');
    expect(boldRun.$2?.fontWeight, FontWeight.bold);
  });

  testWidgets('italic and underline survive', (tester) async {
    final c = FormattedTextEditingController(text: 'one two')
      ..updateFormats([
        const TextSpanFormat(start: 0, end: 3, isItalic: true),
        const TextSpanFormat(start: 4, end: 7, isUnderline: true),
      ]);
    final span = await build(tester, c);
    final r = runs(span);

    expect(r.firstWhere((x) => x.$1 == 'one').$2?.fontStyle, FontStyle.italic);
    expect(r.firstWhere((x) => x.$1 == 'two').$2?.decoration,
        TextDecoration.underline);
  });

  testWidgets('every character survives, whatever the formats', (tester) async {
    const text = 'the quick brown fox';
    final c = FormattedTextEditingController(text: text)
      ..updateFormats([
        const TextSpanFormat(start: 4, end: 9, isBold: true),
        const TextSpanFormat(start: 10, end: 15, isItalic: true),
      ]);
    final span = await build(tester, c);

    expect(runs(span).map((r) => r.$1).join(), text,
        reason: 'text was dropped or duplicated while splitting runs');
  });

  testWidgets('out-of-range formats do not lose text', (tester) async {
    final c = FormattedTextEditingController(text: 'short')
      ..updateFormats([const TextSpanFormat(start: 2, end: 99, isBold: true)]);
    final span = await build(tester, c);

    expect(runs(span).map((r) => r.$1).join(), 'short');
  });

  group('inline #tags', () {
    testWidgets('a #tag is tinted', (tester) async {
      final c = FormattedTextEditingController(text: 'trusting in #faith now');
      final span = await build(tester, c);

      final tag = runs(span).firstWhere((r) => r.$1 == '#faith');
      expect(tag.$2?.backgroundColor, isNotNull);
      expect(tag.$2?.color, isNotNull);
    });

    testWidgets('the tint covers the # and the word, and stops there',
        (tester) async {
      final c = FormattedTextEditingController(text: 'a #faith. b');
      final span = await build(tester, c);
      final r = runs(span);

      expect(r.map((x) => x.$1).join(), 'a #faith. b');
      final tinted =
          r.where((x) => x.$2?.backgroundColor != null).map((x) => x.$1);
      expect(tinted, ['#faith'],
          reason: 'the full stop or the spaces got tinted too');
    });

    testWidgets('plain text carries no tint', (tester) async {
      final c = FormattedTextEditingController(text: 'no tags here');
      final span = await build(tester, c);

      expect(runs(span).where((r) => r.$2?.backgroundColor != null), isEmpty);
    });

    testWidgets('a #tag inside a bold run keeps both', (tester) async {
      // The old algorithm skipped any range overlapping the previous one, so
      // one of these two silently lost. This is the case that forced the
      // rewrite.
      final c = FormattedTextEditingController(text: 'read #faith daily')
        ..updateFormats(
            [const TextSpanFormat(start: 0, end: 17, isBold: true)]);
      final span = await build(tester, c);
      final r = runs(span);

      expect(r.map((x) => x.$1).join(), 'read #faith daily');
      final tag = r.firstWhere((x) => x.$1 == '#faith');
      expect(tag.$2?.backgroundColor, isNotNull, reason: 'tint lost to bold');
      expect(tag.$2?.fontWeight, FontWeight.bold, reason: 'bold lost to tint');
      expect(r.firstWhere((x) => x.$1 == 'read ').$2?.fontWeight,
          FontWeight.bold,
          reason: 'bold should continue either side of the tag');
    });

    testWidgets('the tint differs between themes', (tester) async {
      final light = FormattedTextEditingController(text: '#faith');
      final lightSpan = await build(tester, light);
      final lightRun = runs(lightSpan).first.$2;

      final dark = FormattedTextEditingController(text: '#faith');
      final darkSpan =
          await build(tester, dark, brightness: Brightness.dark);
      final darkRun = runs(darkSpan).first.$2;

      expect(lightRun?.color, isNot(darkRun?.color),
          reason: 'one theme is wearing the other theme\'s ink');
    });
  });
}
