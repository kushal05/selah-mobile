import 'package:flutter/material.dart';

import '../../../domain/models/text_span_format.dart';
import '../../../domain/services/inline_tag_parser.dart';
import '../tagged_text.dart';

/// Custom TextEditingController that renders formatted text directly
/// This ensures cursor position matches the visual text layout
class FormattedTextEditingController extends TextEditingController {
  List<TextSpanFormat> _formats;

  FormattedTextEditingController({
    super.text,
    List<TextSpanFormat>? formats,
  }) : _formats = formats ?? [];

  /// Update the formats to render
  /// Note: Does not call notifyListeners() because this is typically called
  /// during build when the widget is already rebuilding
  void updateFormats(List<TextSpanFormat> formats) {
    _formats = formats;
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final effectiveStyle = style ?? const TextStyle();
    final tags = InlineTagParser.parse(text);

    if ((_formats.isEmpty && tags.isEmpty) || text.isEmpty) {
      return TextSpan(text: text, style: effectiveStyle);
    }

    final validFormats = _formats
        .where((f) => f.start < text.length && f.end > 0 && f.start < f.end)
        .toList();

    if (validFormats.isEmpty && tags.isEmpty) {
      return TextSpan(text: text, style: effectiveStyle);
    }

    // Cut the text at every point where the styling changes, then emit one run
    // per gap.
    //
    // The previous version walked the format list and skipped any range that
    // started before the last one ended. That was fine when the only ranges
    // were the formats themselves, but a tag sitting inside a bold run is an
    // overlap by construction, and skipping meant one of the two silently lost
    // — a #tag inside bold text would not be tinted, or the bold would stop at
    // the tag. Splitting on boundaries lets a character carry both.
    final boundaries = <int>{0, text.length};
    for (final f in validFormats) {
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

      var runStyle = effectiveStyle;
      for (final f in validFormats) {
        if (f.start <= start && f.end >= end) {
          runStyle = _applyFormat(runStyle, f);
        }
      }
      final isTag = tags.any((t) => t.start <= start && t.end >= end);
      if (isTag) runStyle = _applyTagTint(runStyle, context);

      spans.add(TextSpan(text: text.substring(start, end), style: runStyle));
    }

    return TextSpan(
      children: spans.isEmpty
          ? [TextSpan(text: text, style: effectiveStyle)]
          : spans,
    );
  }

  /// Delegates to [inlineTagStyle] so the editor and the read-only detail
  /// screen cannot drift apart about what a tag looks like.
  static TextStyle _applyTagTint(TextStyle style, BuildContext context) =>
      inlineTagStyle(style, Theme.of(context).brightness);

  static TextStyle _applyFormat(TextStyle style, TextSpanFormat format) {
    return style.copyWith(
      fontWeight: format.isBold ? FontWeight.bold : style.fontWeight,
      fontStyle: format.isItalic ? FontStyle.italic : style.fontStyle,
      decoration: TextDecoration.combine([
        if (format.isUnderline) TextDecoration.underline,
        if (format.isStrikethrough) TextDecoration.lineThrough,
      ]),
    );
  }
}
