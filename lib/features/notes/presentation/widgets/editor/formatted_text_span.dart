import 'package:flutter/material.dart';

import '../../../domain/models/text_span_format.dart';

/// Builds a [TextSpan] tree that applies [formats] over [text] on top of
/// [baseStyle].
///
/// Shared by the editor's `FormattedTextEditingController` (live editing) and
/// the read-only note detail view so both render inline bold/italic/underline/
/// strikethrough identically. Format ranges are clamped to the text bounds and
/// de-overlapped so malformed ranges can never throw.
TextSpan buildFormattedTextSpan({
  required String text,
  required List<TextSpanFormat> formats,
  required TextStyle baseStyle,
}) {
  if (formats.isEmpty || text.isEmpty) {
    return TextSpan(text: text, style: baseStyle);
  }

  // Filter out invalid formats and clamp indices to text bounds
  final validFormats = formats
      .where((f) => f.start < text.length && f.end > 0 && f.start < f.end)
      .toList();

  if (validFormats.isEmpty) {
    return TextSpan(text: text, style: baseStyle);
  }

  // Sort formats by start position
  validFormats.sort((a, b) => a.start.compareTo(b.start));

  final spans = <TextSpan>[];
  int currentIndex = 0;

  for (final format in validFormats) {
    // Clamp format indices to valid range
    final startIndex = format.start.clamp(0, text.length);
    final endIndex = format.end.clamp(0, text.length);

    // Skip if invalid range after clamping
    if (startIndex >= endIndex) continue;

    // Skip if this format is entirely before current position (already processed)
    if (endIndex <= currentIndex) continue;

    // Adjust start to avoid overlapping with already processed text
    final effectiveStart = startIndex < currentIndex ? currentIndex : startIndex;

    // Add unstyled text before this format (if any gap exists)
    if (effectiveStart > currentIndex) {
      spans.add(TextSpan(
        text: text.substring(currentIndex, effectiveStart),
        style: baseStyle,
      ));
    }

    // Add styled text (only the non-overlapping portion)
    spans.add(TextSpan(
      text: text.substring(effectiveStart, endIndex),
      style: _applyFormat(baseStyle, format),
    ));

    currentIndex = endIndex;
  }

  // Add remaining unstyled text
  if (currentIndex < text.length) {
    spans.add(TextSpan(
      text: text.substring(currentIndex),
      style: baseStyle,
    ));
  }

  return TextSpan(
    children: spans.isEmpty ? [TextSpan(text: text, style: baseStyle)] : spans,
  );
}

TextStyle _applyFormat(TextStyle style, TextSpanFormat format) {
  return style.copyWith(
    fontWeight: format.isBold ? FontWeight.bold : style.fontWeight,
    fontStyle: format.isItalic ? FontStyle.italic : style.fontStyle,
    // Merge with any decoration already on the base style (e.g. the
    // line-through applied to a checked checkbox) so formatted spans don't
    // silently drop it.
    decoration: TextDecoration.combine([
      if (style.decoration != null) style.decoration!,
      if (format.isUnderline) TextDecoration.underline,
      if (format.isStrikethrough) TextDecoration.lineThrough,
    ]),
  );
}
