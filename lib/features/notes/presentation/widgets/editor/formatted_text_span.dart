import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../domain/models/text_span_format.dart';

/// Monospace fallbacks for inline code and code blocks. `monospace` only
/// resolves on Android; Menlo (iOS/macOS) and Courier New (Windows) keep code
/// visually distinct everywhere else.
const List<String> kMonospaceFallback = <String>[
  'monospace',
  'Menlo',
  'Courier New',
];

/// Schemes a note's inline link may be opened with.
///
/// Link targets come from pasted or SHARED note content, so they are untrusted:
/// anything outside this set (javascript:, intent:, file:, data:, …) must never
/// reach the OS launcher.
const Set<String> kSafeLinkSchemes = {'http', 'https', 'mailto', 'tel'};

/// Whether [url] is a well-formed absolute link safe to hand to the launcher.
bool isSafeNoteLink(String url) {
  final uri = Uri.tryParse(url.trim());
  if (uri == null || !uri.hasScheme) return false;
  return kSafeLinkSchemes.contains(uri.scheme.toLowerCase());
}

/// Builds a [TextSpan] tree that applies [formats] over [text] on top of
/// [baseStyle].
///
/// Shared by the editor's `FormattedTextEditingController` (live editing) and
/// the read-only note detail view so both render inline bold/italic/underline/
/// strikethrough/code/links identically. Format ranges are clamped to the text
/// bounds and de-overlapped so malformed ranges can never throw.
///
/// [linkColor] themes hyperlink spans (defaults to a blue accent when null).
/// [recognizerBuilder] optionally supplies a gesture recognizer for each link
/// span; the CALLER owns the returned recognizer's lifecycle (see
/// [FormattedText], which manages disposal). Pass null for non-interactive
/// rendering such as inside an editable text field, where a tap must place the
/// caret rather than follow the link.
TextSpan buildFormattedTextSpan({
  required String text,
  required List<TextSpanFormat> formats,
  required TextStyle baseStyle,
  Color? linkColor,
  GestureRecognizer? Function(TextSpanFormat format)? recognizerBuilder,
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
    final isLink = format.link != null && format.link!.isNotEmpty;
    spans.add(TextSpan(
      text: text.substring(effectiveStart, endIndex),
      style: _applyFormat(baseStyle, format, linkColor),
      recognizer: isLink ? recognizerBuilder?.call(format) : null,
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

TextStyle _applyFormat(
  TextStyle style,
  TextSpanFormat format,
  Color? linkColor,
) {
  final isLink = format.link != null && format.link!.isNotEmpty;
  return style.copyWith(
    fontWeight: format.isBold ? FontWeight.bold : style.fontWeight,
    fontStyle: format.isItalic ? FontStyle.italic : style.fontStyle,
    // Inline code renders in a monospace face with a subtle tint. Links adopt
    // the supplied accent. Both leave the surrounding text untouched.
    fontFamily: format.isCode ? kMonospaceFallback.first : style.fontFamily,
    fontFamilyFallback: format.isCode ? kMonospaceFallback : style.fontFamilyFallback,
    backgroundColor: format.isCode
        ? const Color(0x14808080)
        : style.backgroundColor,
    color: isLink ? (linkColor ?? const Color(0xFF2563EB)) : style.color,
    // Merge with any decoration already on the base style (e.g. the
    // line-through applied to a checked checkbox) so formatted spans don't
    // silently drop it.
    decoration: TextDecoration.combine([
      if (style.decoration != null) style.decoration!,
      if (format.isUnderline || isLink) TextDecoration.underline,
      if (format.isStrikethrough) TextDecoration.lineThrough,
    ]),
  );
}

/// Renders [text] with [formats] as read-only rich text, with tappable links.
///
/// Owns the lifecycle of the link [TapGestureRecognizer]s — they are rebuilt
/// only when the set of link URLs changes and disposed with the widget, which a
/// plain `Text.rich` in a stateless build cannot do without leaking.
class FormattedText extends StatefulWidget {
  final String text;
  final List<TextSpanFormat> formats;
  final TextStyle? style;

  /// Called with the URL when a link span is tapped. When null, links render
  /// styled but are not interactive.
  final ValueChanged<String>? onLinkTap;

  const FormattedText({
    super.key,
    required this.text,
    required this.formats,
    this.style,
    this.onLinkTap,
  });

  @override
  State<FormattedText> createState() => _FormattedTextState();
}

class _FormattedTextState extends State<FormattedText> {
  /// One recognizer per distinct URL, shared by every span carrying it.
  final Map<String, TapGestureRecognizer> _recognizers = {};

  @override
  void initState() {
    super.initState();
    _syncRecognizers();
  }

  @override
  void didUpdateWidget(FormattedText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.onLinkTap != widget.onLinkTap ||
        !setEquals(_urls(oldWidget.formats), _urls(widget.formats))) {
      _syncRecognizers();
    }
  }

  Set<String> _urls(List<TextSpanFormat> formats) => formats
      .where((f) => f.link != null && f.link!.isNotEmpty)
      .map((f) => f.link!)
      .toSet();

  void _syncRecognizers() {
    final wanted = widget.onLinkTap == null ? <String>{} : _urls(widget.formats);

    for (final url in _recognizers.keys.toList()) {
      if (!wanted.contains(url)) {
        _recognizers.remove(url)!.dispose();
      }
    }
    for (final url in wanted) {
      _recognizers.putIfAbsent(
        url,
        () => TapGestureRecognizer()..onTap = () => widget.onLinkTap?.call(url),
      );
    }
  }

  @override
  void dispose() {
    for (final r in _recognizers.values) {
      r.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.formats.isEmpty) {
      return Text(widget.text, style: widget.style);
    }
    return Text.rich(
      buildFormattedTextSpan(
        text: widget.text,
        formats: widget.formats,
        baseStyle: widget.style ?? const TextStyle(),
        linkColor: Theme.of(context).colorScheme.primary,
        recognizerBuilder: (format) => _recognizers[format.link],
      ),
    );
  }
}
