import 'package:flutter/material.dart';

import '../../../domain/models/text_span_format.dart';
import 'formatted_text_span.dart';

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
    return buildFormattedTextSpan(
      text: text,
      formats: _formats,
      baseStyle: style ?? const TextStyle(),
    );
  }
}
