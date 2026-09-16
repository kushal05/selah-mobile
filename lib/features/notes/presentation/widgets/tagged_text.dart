import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
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

/// Note text with its `#tags` tinted, for read-only surfaces.
class TaggedText extends StatelessWidget {
  final String text;
  final TextStyle? style;

  const TaggedText(this.text, {super.key, this.style});

  @override
  Widget build(BuildContext context) {
    final base = style ?? DefaultTextStyle.of(context).style;
    final tags = InlineTagParser.parse(text);
    if (tags.isEmpty) return Text(text, style: base);

    final tagStyle = inlineTagStyle(base, Theme.of(context).brightness);
    final spans = <TextSpan>[];
    var cursor = 0;

    for (final tag in tags) {
      if (tag.start > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, tag.start)));
      }
      spans.add(TextSpan(
        text: text.substring(tag.start, tag.end),
        style: tagStyle,
      ));
      cursor = tag.end;
    }
    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor)));
    }

    return Text.rich(TextSpan(style: base, children: spans));
  }
}
