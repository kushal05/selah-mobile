import 'dart:convert';

/// Where paragraphs open in each chapter, from the bundled
/// `assets/bible/paragraphs.json`.
///
/// The list comes from the public-domain World English Bible's markup, built by
/// the web client's `tools/build-paragraphs.mjs`, and is shown for every
/// translation: none of our own Bible text carries paragraphs, and English
/// versions paragraph almost alike. Verse 1 is never listed; it always opens
/// one. It is reading furniture, not synced data.
class BibleParagraphData {
  final Map<int, Map<int, Set<int>>> _books;

  const BibleParagraphData._(this._books);

  /// No paragraph data: every chapter reads as one block.
  static const empty = BibleParagraphData._({});

  /// Parses `{ "<bookId>": { "<chapter>": [verse, ...] } }`. Anything that is
  /// not that shape yields [empty], and a bad entry is skipped, so a damaged
  /// asset costs the paragraphs and nothing else.
  factory BibleParagraphData.parse(String source) {
    final Object? json;
    try {
      json = jsonDecode(source);
    } on FormatException {
      return empty;
    }
    if (json is! Map<String, dynamic>) return empty;
    final books = <int, Map<int, Set<int>>>{};
    for (final book in json.entries) {
      final bookId = int.tryParse(book.key);
      final chapters = book.value;
      if (bookId == null || chapters is! Map<String, dynamic>) continue;
      final parsed = <int, Set<int>>{};
      for (final chapter in chapters.entries) {
        final number = int.tryParse(chapter.key);
        final verses = chapter.value;
        if (number == null || verses is! List) continue;
        parsed[number] = {
          for (final v in verses)
            if (v is int && v > 1) v,
        };
      }
      books[bookId] = parsed;
    }
    return BibleParagraphData._(books);
  }

  /// The verses of this chapter that open a paragraph; empty when none.
  Set<int> startsFor(int bookId, int chapter) =>
      _books[bookId]?[chapter] ?? const <int>{};
}
