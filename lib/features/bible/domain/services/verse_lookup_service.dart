import '../models/bible_reference.dart';
import '../../data/bible_repository.dart';
import '../models/bible_book_entity.dart';

/// Resolves Bible verse references to their text from the local SQLite database.
///
/// This service bridges the Notes editor and the Bible database. When a note
/// contains a `bibleReference` block, the block stores only the coordinates
/// (translation, bookId, chapter, verse). This service resolves those
/// coordinates to actual verse text at render time.
///
/// Design decisions:
/// - Lookups are synchronous and fast (<1ms) since the Bible DB is local.
/// - If a verse is missing (e.g., translation not installed), a graceful
///   fallback is returned rather than throwing.
/// - The service does NOT cache results in memory. SQLite's built-in page
///   cache handles this more efficiently than a Dart-side LRU.
/// - Verse text updates automatically when the user switches translations
///   because the lookup uses the current translation parameter.
class VerseLookupService {
  final BibleRepository _repository;

  VerseLookupService(this._repository);

  /// Resolve a [BibleVerseReference] to a list of [BibleVerseText].
  ///
  /// Returns an empty list if the verse(s) cannot be found in the database.
  /// This allows the UI to show a graceful fallback instead of crashing.
  List<BibleVerseText> lookupVerses(BibleVerseReference ref) {
    // Resolve book name to book ID
    final bookId = _resolveBookId(ref.book);
    if (bookId == null) return [];

    final translation = ref.version.toUpperCase();

    if (ref.verses.isEmpty) return [];

    // For a contiguous range, use the optimized range query
    if (_isContiguous(ref.verses)) {
      final entities = _repository.getVerseRange(
        bookId: bookId,
        chapter: ref.chapter,
        verseStart: ref.verses.first,
        verseEnd: ref.verses.last,
        translation: translation,
      );
      return entities
          .map((e) => BibleVerseText(verse: e.verse, content: e.text))
          .toList();
    }

    // Non-contiguous verse list (uncommon but supported)
    final entities = _repository.getVersesByNumbers(
      bookId: bookId,
      chapter: ref.chapter,
      verseNumbers: ref.verses,
      translation: translation,
    );
    return entities
        .map((e) => BibleVerseText(verse: e.verse, content: e.text))
        .toList();
  }

  /// Resolve a single verse by exact coordinates.
  ///
  /// Returns null if the verse is not found.
  BibleVerseText? lookupSingleVerse({
    required int bookId,
    required int chapter,
    required int verse,
    required String translation,
  }) {
    final entity = _repository.getVerse(
      bookId: bookId,
      chapter: chapter,
      verse: verse,
      translation: translation.toUpperCase(),
    );
    if (entity == null) return null;
    return BibleVerseText(verse: entity.verse, content: entity.text);
  }

  /// Resolve a book name (e.g., "John", "1 Corinthians") to its numeric ID.
  ///
  /// Tries full name first, then short name. Returns null if not found.
  int? _resolveBookId(String bookName) {
    if (bookName.isEmpty) return null;

    // Try full name match
    final byName = _repository.getBookByName(bookName);
    if (byName != null) return byName.id;

    // Try short name match
    final byShort = _repository.getBookByShortName(bookName);
    if (byShort != null) return byShort.id;

    return null;
  }

  /// Check if a list of verse numbers forms a contiguous range.
  bool _isContiguous(List<int> verses) {
    if (verses.length <= 1) return true;
    for (int i = 1; i < verses.length; i++) {
      if (verses[i] != verses[i - 1] + 1) return false;
    }
    return true;
  }

  /// Get the book entity for a given book name.
  /// Useful for building display references.
  BibleBookEntity? getBook(String bookName) {
    return _repository.getBookByName(bookName) ??
        _repository.getBookByShortName(bookName);
  }

  /// Get the book entity by its numeric ID.
  BibleBookEntity? getBookById(int bookId) {
    return _repository.getBookById(bookId);
  }
}
