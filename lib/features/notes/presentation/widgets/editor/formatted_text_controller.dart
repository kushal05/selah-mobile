import 'package:flutter/material.dart';

import '../../../domain/models/text_span_format.dart';
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
    // Delegates: the read-only detail screen draws the same text through
    // buildNoteTextSpan, and two copies of the run-splitting logic would let
    // a note look different depending on whether you were editing it. That is
    // exactly how the detail screen came to drop bold and italic entirely.
    return buildNoteTextSpan(
      text: text,
      formats: _formats,
      base: style ?? const TextStyle(),
      brightness: Theme.of(context).brightness,
    );
  }
}
