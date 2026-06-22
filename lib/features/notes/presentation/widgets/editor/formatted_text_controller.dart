import 'package:flutter/material.dart';

import '../../../domain/models/text_span_format.dart';

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

    if (_formats.isEmpty || text.isEmpty) {
      return TextSpan(text: text, style: effectiveStyle);
    }

    // Filter out invalid formats and clamp indices to text bounds
    final validFormats = _formats
        .where((f) => f.start < text.length && f.end > 0 && f.start < f.end)
        .toList();

    if (validFormats.isEmpty) {
      return TextSpan(text: text, style: effectiveStyle);
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
          style: effectiveStyle,
        ));
      }

      // Add styled text (only the non-overlapping portion)
      spans.add(TextSpan(
        text: text.substring(effectiveStart, endIndex),
        style: _applyFormat(effectiveStyle, format),
      ));

      currentIndex = endIndex;
    }

    // Add remaining unstyled text
    if (currentIndex < text.length) {
      spans.add(TextSpan(
        text: text.substring(currentIndex),
        style: effectiveStyle,
      ));
    }

    return TextSpan(
      children: spans.isEmpty ? [TextSpan(text: text, style: effectiveStyle)] : spans,
    );
  }

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
