// A note reads the same whether or not you are editing it.
//
// The read-only detail screen drew every block through `TaggedText`, which
// tinted `#tags` and nothing else — it took no formats at all. So bold, italic,
// underline and strikethrough were visible while typing and silently gone the
// moment you left the editor.
//
// Both surfaces now go through one `buildNoteTextSpan`, which is the point:
// two implementations of run-splitting are what let them diverge in the first
// place.

import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:notify/features/notes/domain/models/text_span_format.dart';
import 'package:notify/features/notes/presentation/widgets/editor/formatted_text_controller.dart';
import 'package:notify/features/notes/presentation/widgets/tagged_text.dart';

/// Every styled run the span carries, flattened.
List<TextStyle> _runs(TextSpan span) {
  final out = <TextStyle>[];
  span.visitChildren((s) {
    if (s is TextSpan && s.text != null && s.text!.isNotEmpty) {
      out.add(s.style ?? const TextStyle());
    }
    return true;
  });
  return out;
}

TextSpan _span(String text, List<TextSpanFormat> formats,
        {Brightness brightness = Brightness.light}) =>
    buildNoteTextSpan(
      text: text,
      formats: formats,
      base: const TextStyle(fontSize: 16),
      brightness: brightness,
    );

void main() {
  test('bold survives into the read-only span', () {
    final span = _span('hello world',
        const [TextSpanFormat(start: 0, end: 5, isBold: true)]);
    final bold = _runs(span).where((s) => s.fontWeight == FontWeight.bold);
    expect(bold, isNotEmpty, reason: 'the bold run must reach the preview');
  });

  test('italic, underline and strikethrough all survive', () {
    final span = _span('abcdefghijkl', const [
      TextSpanFormat(start: 0, end: 3, isItalic: true),
      TextSpanFormat(start: 3, end: 6, isUnderline: true),
      TextSpanFormat(start: 6, end: 9, isStrikethrough: true),
    ]);
    final runs = _runs(span);
    expect(runs.any((s) => s.fontStyle == FontStyle.italic), isTrue);
    expect(
        runs.any((s) =>
            s.decoration?.contains(TextDecoration.underline) ?? false),
        isTrue);
    expect(
        runs.any((s) =>
            s.decoration?.contains(TextDecoration.lineThrough) ?? false),
        isTrue);
  });

  test('a tag inside a bold run keeps both', () {
    // The overlap case: skipping either range would lose one of the two.
    final span = _span('read #faith daily',
        const [TextSpanFormat(start: 0, end: 17, isBold: true)]);
    final tagRun = _runs(span)
        .where((s) => s.backgroundColor != null)
        .toList();
    expect(tagRun, isNotEmpty, reason: 'the tag must still be tinted');
    expect(tagRun.first.fontWeight, isNot(FontWeight.normal),
        reason: 'and must not come out lighter than the words around it');
  });

  test('two formats over the same range both survive', () {
    // The toolbar stores bold and underline as separate formats when you
    // apply them one after the other. Rebuilding `decoration` per format made
    // the second erase the first, so bold-and-underlined came out bold and
    // plain — in the editor as well as the preview, since both run this.
    final span = _span('important', const [
      TextSpanFormat(start: 0, end: 9, isUnderline: true),
      TextSpanFormat(start: 0, end: 9, isBold: true),
    ]);
    final run = _runs(span).single;

    expect(run.fontWeight, FontWeight.bold);
    expect(run.decoration?.contains(TextDecoration.underline), isTrue,
        reason: 'the underline must survive the bold being applied after it');
  });

  test('strikethrough and underline together keep both marks', () {
    final span = _span('gone', const [
      TextSpanFormat(start: 0, end: 4, isUnderline: true),
      TextSpanFormat(start: 0, end: 4, isStrikethrough: true),
    ]);
    final run = _runs(span).single;

    expect(run.decoration?.contains(TextDecoration.underline), isTrue);
    expect(run.decoration?.contains(TextDecoration.lineThrough), isTrue);
  });

  test('unformatted text is left alone', () {
    final span = _span('plain text', const []);
    expect(span.text, 'plain text');
    expect(span.children, isNull);
  });

  test('the span always spells out exactly the text it was given', () {
    // The invariant that protects typing, not just reading. The editor's
    // TextEditingController returns this span, and a caret is positioned
    // against the span's plain text — if splitting into runs ever dropped or
    // duplicated a character, selection and backspace would land in the wrong
    // place while the text still looked right.
    //
    // Randomised because the hazard is in the arithmetic: ranges that overrun
    // the text, invert, sit at zero width, or overlap a #tag.
    final rnd = Random(20261001);
    const alphabet = 'ab #tag\u00e9\u0301 x\n';

    for (var i = 0; i < 500; i++) {
      final text = List.generate(
          rnd.nextInt(24), (_) => alphabet[rnd.nextInt(alphabet.length)]).join();
      final formats = List.generate(
        rnd.nextInt(4),
        (_) => TextSpanFormat(
          start: rnd.nextInt(30) - 5,
          end: rnd.nextInt(30) - 5,
          isBold: rnd.nextBool(),
          isItalic: rnd.nextBool(),
          isUnderline: rnd.nextBool(),
          isStrikethrough: rnd.nextBool(),
        ),
      );

      final span = buildNoteTextSpan(
        text: text,
        formats: formats,
        base: const TextStyle(),
        brightness: Brightness.dark,
      );

      expect(span.toPlainText(), text,
          reason: 'formats ${formats.map((f) => "${f.start}-${f.end}").toList()} '
              'changed the text itself');
    }
  });

  testWidgets('TaggedText renders the formats it is given', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: TaggedText(
          'hello world',
          formats: [TextSpanFormat(start: 0, end: 5, isBold: true)],
        ),
      ),
    ));

    final rich = tester.widget<Text>(find.byType(Text));
    final runs = _runs(rich.textSpan as TextSpan);
    expect(runs.any((s) => s.fontWeight == FontWeight.bold), isTrue);
  });

  testWidgets('the editor still renders formats through a real field',
      (tester) async {
    // The controller's buildTextSpan was rewritten to delegate, and it is what
    // a TextField paints and positions the caret against. Exercised through an
    // actual field rather than by calling the function, because the delegation
    // is the thing that could have broken.
    final controller = FormattedTextEditingController(text: 'hello world');
    controller.updateFormats(
        const [TextSpanFormat(start: 0, end: 5, isBold: true)]);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: TextField(controller: controller)),
    ));
    await tester.pump();

    final span = controller.buildTextSpan(
      context: tester.element(find.byType(EditableText)),
      style: const TextStyle(fontSize: 16),
      withComposing: false,
    );

    expect(_runs(span).any((s) => s.fontWeight == FontWeight.bold), isTrue);
    expect(span.toPlainText(), 'hello world',
        reason: 'the caret is positioned against this text');
  });

  group('a ticked checkbox', () {
    // The checkbox hands in a base style that already carries lineThrough and
    // a block that may also have formats — an interaction none of the other
    // blocks have. Rebuilding decoration per format used to drop the strike.
    TextSpan ticked(String text, List<TextSpanFormat> formats) =>
        buildNoteTextSpan(
          text: text,
          formats: formats,
          base: const TextStyle(decoration: TextDecoration.lineThrough),
          brightness: Brightness.light,
        );

    test('keeps its strikethrough under a bold run', () {
      final runs = _runs(ticked(
          'buy milk', const [TextSpanFormat(start: 0, end: 3, isBold: true)]));

      expect(runs.any((s) => s.fontWeight == FontWeight.bold), isTrue);
      expect(
          runs.every((s) =>
              s.decoration?.contains(TextDecoration.lineThrough) ?? false),
          isTrue,
          reason: 'every run of a ticked item stays struck through');
    });

    test('keeps it under a #tag too', () {
      final runs = _runs(ticked('buy #milk today', const []));

      expect(runs.any((s) => s.backgroundColor != null), isTrue,
          reason: 'the tag is still tinted');
      expect(
          runs.every((s) =>
              s.decoration?.contains(TextDecoration.lineThrough) ?? false),
          isTrue);
    });
  });

  test('every block that carries text draws it through TaggedText', () {
    // Two failure modes, and the first version of this test only caught one.
    //
    // It counted TaggedText call sites and checked each passed `formats:`,
    // which says nothing about a block type that never used TaggedText at all
    // — and `checkbox` did not. Its text was a plain `Text`, so a ticked item
    // lost its bold and its #tag tint while the paragraph above it kept both.
    //
    // So this asserts on the block types instead: every case in the renderer
    // that draws `block.content` must do it through TaggedText, with formats.
    final src = File(
      'lib/features/notes/presentation/screens/note_detail_screen.dart',
    ).readAsLinesSync()
        .map((l) => l.replaceFirst(RegExp(r'\s*//.*$'), ''))
        .join('\n');

    // `block.content` rendered by a plain Text is the defect.
    final plain = RegExp(r'Text\(\s*\n\s*block\.content').allMatches(src)
        .where((m) => !src.substring(0, m.start).endsWith('Tagged'))
        .length;
    expect(plain, 0,
        reason: 'a block type draws block.content with a plain Text, so it '
            'loses formatting and tags');

    final calls = RegExp(r'TaggedText\(').allMatches(src).length;
    final wired = RegExp(r'formats:\s*block\.formats').allMatches(src).length;
    expect(calls, greaterThan(0), reason: 'the preview must draw note text');
    expect(wired, calls,
        reason: 'all $calls TaggedText call sites must pass block.formats; '
            'only $wired do, so those blocks lose their bold and italic');
  });
}
