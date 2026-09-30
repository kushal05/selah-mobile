import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/models/text_span_format.dart';
import '../../domain/services/inline_tag_parser.dart';

/// How a `#tag` is painted inside note text.
///
/// One definition, used by the editor's controller and by the read-only detail
/// screen. A note that looked different depending on whether you were editing
/// it would read as a bug, and two copies of this would drift.
///
/// A background tint rather than a rounded chip: a chip needs a WidgetSpan,
/// and a widget inside an editable TextField breaks caret placement, selection
/// and backspace.
TextStyle inlineTagStyle(TextStyle base, Brightness brightness) {
  final existing = base.fontWeight ?? FontWeight.normal;
  return base.copyWith(
    backgroundColor: AppTheme.brandPurple
        .withValues(alpha: brightness == Brightness.dark ? 0.26 : 0.14),
    color: AppTheme.inkOnTintFor(AppTheme.brandPurple, brightness),
    // Nudge the weight up, never down — a tag inside a bold run should not
    // come out lighter than the words around it.
    fontWeight:
        existing.value >= FontWeight.w600.value ? existing : FontWeight.w600,
  );
}

/// Builds the styled runs for a block of note text.
///
/// One implementation, used by the editor's controller and by the read-only
/// detail screen. The detail screen had no formatting at all — it drew
/// `Text(block.content)` and dropped every bold, italic, underline and
/// strikethrough the moment you left the editor, so a note looked different
/// depending on whether you happened to be editing it.
///
/// Cuts the text at every point where the styling changes and emits one run
/// per gap, rather than walking the formats in order. A `#tag` sitting inside
/// a bold run overlaps it by construction, and anything that skips overlapping
/// ranges silently loses one of the two.
TextSpan buildNoteTextSpan({
  required String text,
  required List<TextSpanFormat> formats,
  required TextStyle base,
  required Brightness brightness,
}) {
  final tags = InlineTagParser.parse(text);

  if (text.isEmpty || (formats.isEmpty && tags.isEmpty)) {
    return TextSpan(text: text, style: base);
  }

  final valid = formats
      .where((f) => f.start < text.length && f.end > 0 && f.start < f.end)
      .toList();

  if (valid.isEmpty && tags.isEmpty) {
    return TextSpan(text: text, style: base);
  }

  final boundaries = <int>{0, text.length};
  for (final f in valid) {
    boundaries.add(f.start.clamp(0, text.length));
    boundaries.add(f.end.clamp(0, text.length));
  }
  for (final t in tags) {
    boundaries.add(t.start.clamp(0, text.length));
    boundaries.add(t.end.clamp(0, text.length));
  }

  final cuts = boundaries.toList()..sort();
  final spans = <TextSpan>[];

  for (var i = 0; i < cuts.length - 1; i++) {
    final start = cuts[i];
    final end = cuts[i + 1];
    if (start >= end) continue;

    var runStyle = base;
    for (final f in valid) {
      if (f.start <= start && f.end >= end) {
        runStyle = applyNoteFormat(runStyle, f);
      }
    }
    if (tags.any((t) => t.start <= start && t.end >= end)) {
      runStyle = inlineTagStyle(runStyle, brightness);
    }

    spans.add(TextSpan(text: text.substring(start, end), style: runStyle));
  }

  return TextSpan(
    children:
        spans.isEmpty ? [TextSpan(text: text, style: base)] : spans,
  );
}

/// The marks a [TextSpanFormat] puts on a run.
///
/// Decorations accumulate rather than replace. Applying the toolbar's bold and
/// underline one after the other stores them as two formats over the same
/// range, and rebuilding `decoration` from scratch for each one meant the
/// second silently erased the first — bold-and-underlined text came out bold
/// and plain.
TextStyle applyNoteFormat(TextStyle style, TextSpanFormat format) {
  final existing = style.decoration;
  final decorations = <TextDecoration>{
    if (existing != null && existing != TextDecoration.none) existing,
    if (format.isUnderline) TextDecoration.underline,
    if (format.isStrikethrough) TextDecoration.lineThrough,
  };

  return style.copyWith(
    fontWeight: format.isBold ? FontWeight.bold : style.fontWeight,
    fontStyle: format.isItalic ? FontStyle.italic : style.fontStyle,
    decoration: decorations.isEmpty
        ? TextDecoration.none
        : TextDecoration.combine(decorations.toList()),
  );
}

/// Note text with its `#tags` tinted, for read-only surfaces.
class TaggedText extends StatelessWidget {
  final String text;
  final TextStyle? style;

  /// The bold/italic/underline/strikethrough runs stored on the block.
  ///
  /// Required, and deliberately so. Every caller is a note block, and the bug
  /// this widget was changed to fix was precisely that the detail screen drew
  /// block text without handing over its formats. A default of `const []`
  /// would let the next caller reintroduce that silently; requiring it makes
  /// the omission a compile error instead of something a test has to notice.
  /// A caller with genuinely unformatted text writes `formats: const []`.
  final List<TextSpanFormat> formats;

  const TaggedText(this.text,
      {super.key, this.style, required this.formats});

  @override
  Widget build(BuildContext context) {
    final base = style ?? DefaultTextStyle.of(context).style;
    return Text.rich(buildNoteTextSpan(
      text: text,
      formats: formats,
      base: base,
      brightness: Theme.of(context).brightness,
    ));
  }
}
