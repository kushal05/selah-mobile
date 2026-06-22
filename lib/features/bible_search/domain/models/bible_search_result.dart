import 'package:flutter/foundation.dart';

/// Sort options for Bible search results.
enum BibleSearchSortOption {
  frequency('Frequency'),
  books('Books');

  final String label;
  const BibleSearchSortOption(this.label);
}

/// A single Bible verse search result from FTS5, enriched with book metadata
/// from the pre-populated Bible SQLite database.
@immutable
class BibleSearchResult {
  /// Markers inserted by FTS5 highlight() to delimit matched terms.
  static const hlOpen = '\u00AB'; // «
  static const hlClose = '\u00BB'; // »

  final int id;
  final String translation;
  final int bookId;
  final int chapter;
  final int verse;
  final String text;

  /// Book name resolved via JOIN with bible_books (e.g. "John").
  final String bookName;

  /// 0 = Old Testament, 1 = New Testament.
  final int testament;

  /// Verse text with FTS5 highlight markers around matched terms.
  final String highlightedText;

  const BibleSearchResult({
    required this.id,
    required this.translation,
    required this.bookId,
    required this.chapter,
    required this.verse,
    required this.text,
    required this.bookName,
    required this.testament,
    required this.highlightedText,
  });

  factory BibleSearchResult.fromRow(Map<String, dynamic> row) {
    return BibleSearchResult(
      id: row['id'] as int,
      translation: row['translation'] as String,
      bookId: row['book_id'] as int,
      chapter: row['chapter'] as int,
      verse: row['verse'] as int,
      text: row['text'] as String,
      bookName: row['book_name'] as String,
      testament: row['testament'] as int,
      highlightedText: row['highlighted_text'] as String,
    );
  }

  /// Display reference: "John 3:16 (KJV)"
  String get displayReference =>
      '$bookName $chapter:$verse (${translation.toUpperCase()})';

  /// Short reference without translation: "John 3:16"
  String get shortReference => '$bookName $chapter:$verse';

  /// Full copyable text with reference and verse content.
  String get copyText => '$displayReference\n$text';

  bool get isOldTestament => testament == 0;
  bool get isNewTestament => testament == 1;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BibleSearchResult &&
          id == other.id &&
          translation == other.translation;

  @override
  int get hashCode => Object.hash(id, translation);
}

/// Active filter state for Bible verse search.
///
/// All fields are sets: an empty set means "no filter" (all values).
/// A non-empty set restricts results to matching items.
@immutable
class BibleSearchFilters {
  /// 0 = OT, 1 = NT. Empty = all.
  final Set<int> testaments;

  /// Book IDs (1..66). Empty = all.
  final Set<int> bookIds;

  /// Translation codes (e.g. "KJV"). Empty = all.
  final Set<String> translations;

  const BibleSearchFilters({
    this.testaments = const {},
    this.bookIds = const {},
    this.translations = const {},
  });

  bool get hasActiveFilters =>
      testaments.isNotEmpty || bookIds.isNotEmpty || translations.isNotEmpty;

  BibleSearchFilters copyWith({
    Set<int>? testaments,
    Set<int>? bookIds,
    Set<String>? translations,
  }) {
    return BibleSearchFilters(
      testaments: testaments ?? this.testaments,
      bookIds: bookIds ?? this.bookIds,
      translations: translations ?? this.translations,
    );
  }

  static const empty = BibleSearchFilters();
}
