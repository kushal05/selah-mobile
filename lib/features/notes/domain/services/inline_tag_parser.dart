import 'package:flutter/foundation.dart';

/// One `#tag` found in a block's text.
@immutable
class InlineTag {
  /// Index of the `#`, inclusive.
  final int start;

  /// Index just past the last character of the word, exclusive.
  final int end;

  /// The tag name without the `#`, already normalised to lowercase.
  final String name;

  const InlineTag({
    required this.start,
    required this.end,
    required this.name,
  });

  @override
  bool operator ==(Object other) =>
      other is InlineTag &&
      other.start == start &&
      other.end == end &&
      other.name == name;

  @override
  int get hashCode => Object.hash(start, end, name);

  @override
  String toString() => 'InlineTag($start..$end, $name)';
}

/// Finds `#tag` words in note text.
///
/// One parser, used by both the thing that paints the tint and the thing that
/// puts the tag on the note. Two regexes would eventually disagree, and the
/// disagreement would look like a tag that is highlighted but not saved.
class InlineTagParser {
  InlineTagParser._();

  /// `#` must start the text or follow whitespace, so a URL fragment
  /// (`example.com#section`) and a C# in prose are left alone. The word runs
  /// over letters, digits, underscore and hyphen in any script — `\w` would
  /// exclude accents, and this app is used in more than English.
  static final _pattern = RegExp(
    r'(?<=^|\s)#([\p{L}\p{N}_-]+)',
    unicode: true,
    multiLine: true,
  );

  /// Every tag in [text], in the order they appear.
  static List<InlineTag> parse(String text) {
    if (!text.contains('#')) return const [];
    return _pattern
        .allMatches(text)
        .map((m) => InlineTag(
              start: m.start,
              end: m.end,
              // Lowercased here so the name matches what TagRepository
              // stores; "#Faith" and "#faith" are the same tag.
              name: m.group(1)!.toLowerCase(),
            ))
        .toList(growable: false);
  }

  /// The distinct tag names in [text].
  static Set<String> names(String text) =>
      parse(text).map((t) => t.name).toSet();
}
