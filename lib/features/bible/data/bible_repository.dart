import 'package:flutter/foundation.dart';
import 'package:sqlite3/sqlite3.dart';

import '../domain/models/bible_book_entity.dart';
import '../domain/models/bible_verse_entity.dart';
import 'bible_database_service.dart';

/// Read-only repository for querying the Bible SQLite database.
///
/// Design decisions:
/// - All queries are synchronous (package:sqlite3 is sync). The Bible DB is
///   local and small (~4 MB), so queries complete in <1ms. Wrapping in
///   Future/isolate adds complexity with no measurable benefit.
/// - This repository is the ONLY code that touches the Bible DB. It is
///   completely isolated from the app's sync database, global search, and
///   songs search.
/// - Methods return domain entities, never raw rows.
class BibleRepository {
  final BibleDatabaseService _dbService;

  BibleRepository(this._dbService);

  Database get _db => _dbService.db;

  // ---------------------------------------------------------------------------
  // Book queries
  // ---------------------------------------------------------------------------

  /// All 66 books ordered by canonical sort_order.
  List<BibleBookEntity> getAllBooks() {
    try {
      final rows = _db.select('SELECT * FROM bible_books ORDER BY sort_order');
      return rows.map((r) => BibleBookEntity.fromRow(r)).toList();
    } on SqliteException catch (e) {
      debugPrint('BibleRepository.getAllBooks() failed: $e');
      return [];
    }
  }

  /// Books filtered by testament (0 = OT, 1 = NT), ordered by sort_order.
  List<BibleBookEntity> getBooksByTestament(int testament) {
    try {
      final rows = _db.select(
        'SELECT * FROM bible_books WHERE testament = ? ORDER BY sort_order',
        [testament],
      );
      return rows.map((r) => BibleBookEntity.fromRow(r)).toList();
    } on SqliteException catch (e) {
      debugPrint('BibleRepository.getBooksByTestament() failed: $e');
      return [];
    }
  }

  /// Find a single book by its ID (1..66).
  BibleBookEntity? getBookById(int bookId) {
    try {
      final rows = _db.select(
        'SELECT * FROM bible_books WHERE id = ?',
        [bookId],
      );
      if (rows.isEmpty) return null;
      return BibleBookEntity.fromRow(rows.first);
    } on SqliteException catch (e) {
      debugPrint('BibleRepository.getBookById() failed: $e');
      return null;
    }
  }

  /// Find a book by name (case-insensitive exact match).
  BibleBookEntity? getBookByName(String name) {
    try {
      final rows = _db.select(
        'SELECT * FROM bible_books WHERE LOWER(name) = LOWER(?)',
        [name],
      );
      if (rows.isEmpty) return null;
      return BibleBookEntity.fromRow(rows.first);
    } on SqliteException catch (e) {
      debugPrint('BibleRepository.getBookByName() failed: $e');
      return null;
    }
  }

  /// Find a book by short name (case-insensitive exact match).
  BibleBookEntity? getBookByShortName(String shortName) {
    try {
      final rows = _db.select(
        'SELECT * FROM bible_books WHERE LOWER(short_name) = LOWER(?)',
        [shortName],
      );
      if (rows.isEmpty) return null;
      return BibleBookEntity.fromRow(rows.first);
    } on SqliteException catch (e) {
      debugPrint('BibleRepository.getBookByShortName() failed: $e');
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Chapter queries
  // ---------------------------------------------------------------------------

  /// Distinct chapter numbers for a given book + translation, sorted ascending.
  ///
  /// Example: getChapters(bookId: 43, translation: 'KJV') → [1, 2, ..., 21]
  List<int> getChapters({required int bookId, required String translation}) {
    try {
      final rows = _db.select(
        '''
        SELECT DISTINCT chapter FROM bible_verses
        WHERE book_id = ? AND translation = ?
        ORDER BY chapter
        ''',
        [bookId, translation],
      );
      return rows.map((r) => r['chapter'] as int).toList();
    } on SqliteException catch (e) {
      debugPrint('BibleRepository.getChapters() failed: $e');
      return [];
    }
  }

  // ---------------------------------------------------------------------------
  // Verse queries
  // ---------------------------------------------------------------------------

  /// All verses for a given book + chapter + translation, sorted by verse number.
  ///
  /// Example: getVerses(bookId: 43, chapter: 3, translation: 'KJV')
  List<BibleVerseEntity> getVerses({
    required int bookId,
    required int chapter,
    required String translation,
  }) {
    try {
      final rows = _db.select(
        '''
        SELECT * FROM bible_verses
        WHERE book_id = ? AND chapter = ? AND translation = ?
        ORDER BY verse
        ''',
        [bookId, chapter, translation],
      );
      return rows.map((r) => BibleVerseEntity.fromRow(r)).toList();
    } on SqliteException catch (e) {
      debugPrint('BibleRepository.getVerses() failed: $e');
      return [];
    }
  }

  /// Fetch a single verse by exact coordinates.
  ///
  /// Returns null if the verse does not exist in the database.
  BibleVerseEntity? getVerse({
    required int bookId,
    required int chapter,
    required int verse,
    required String translation,
  }) {
    try {
      final rows = _db.select(
        '''
        SELECT * FROM bible_verses
        WHERE book_id = ? AND chapter = ? AND verse = ? AND translation = ?
        ''',
        [bookId, chapter, verse, translation],
      );
      if (rows.isEmpty) return null;
      return BibleVerseEntity.fromRow(rows.first);
    } on SqliteException catch (e) {
      debugPrint('BibleRepository.getVerse() failed: $e');
      return null;
    }
  }

  /// Fetch a range of verses (inclusive).
  ///
  /// Example: getVerseRange(bookId: 43, chapter: 3, verseStart: 16,
  ///          verseEnd: 18, translation: 'KJV')
  List<BibleVerseEntity> getVerseRange({
    required int bookId,
    required int chapter,
    required int verseStart,
    required int verseEnd,
    required String translation,
  }) {
    try {
      final rows = _db.select(
        '''
        SELECT * FROM bible_verses
        WHERE book_id = ? AND chapter = ? AND verse >= ? AND verse <= ?
              AND translation = ?
        ORDER BY verse
        ''',
        [bookId, chapter, verseStart, verseEnd, translation],
      );
      return rows.map((r) => BibleVerseEntity.fromRow(r)).toList();
    } on SqliteException catch (e) {
      debugPrint('BibleRepository.getVerseRange() failed: $e');
      return [];
    }
  }

  /// Fetch specific verse numbers (for non-contiguous selections).
  List<BibleVerseEntity> getVersesByNumbers({
    required int bookId,
    required int chapter,
    required List<int> verseNumbers,
    required String translation,
  }) {
    if (verseNumbers.isEmpty) return [];

    // Build a parameterized IN clause
    final placeholders = List.filled(verseNumbers.length, '?').join(', ');
    final params = <Object>[bookId, chapter, translation, ...verseNumbers];

    try {
      final rows = _db.select(
        '''
        SELECT * FROM bible_verses
        WHERE book_id = ? AND chapter = ? AND translation = ?
              AND verse IN ($placeholders)
        ORDER BY verse
        ''',
        params,
      );
      return rows.map((r) => BibleVerseEntity.fromRow(r)).toList();
    } on SqliteException catch (e) {
      debugPrint('BibleRepository.getVersesByNumbers() failed: $e');
      return [];
    }
  }

  // ---------------------------------------------------------------------------
  // FTS5 full-text search
  // ---------------------------------------------------------------------------

  /// Search verse text using FTS5.
  ///
  /// This is scoped ONLY to the Bible database. It does NOT search notes,
  /// songs, or any other app data.
  ///
  /// [query] is passed directly to FTS5 MATCH, so it supports:
  ///   - Simple terms: "love"
  ///   - Phrases: '"God so loved"'
  ///   - Boolean: "love AND world"
  ///   - Prefix: "lov*"
  ///
  /// [translation] filters results to a specific translation.
  /// [limit] caps the number of results (default 50).
  List<BibleVerseEntity> searchVerses({
    required String query,
    String? translation,
    int limit = 50,
  }) {
    if (query.trim().isEmpty) return [];

    final translationFilter = translation != null
        ? 'AND bv.translation = ?'
        : '';
    final params = <Object>[
      query,
      if (translation != null) translation,
      limit,
    ];

    try {
      final rows = _db.select(
        '''
        SELECT bv.* FROM bible_verses bv
        JOIN bible_verses_fts fts ON bv.id = fts.rowid
        WHERE fts.text MATCH ?
        $translationFilter
        ORDER BY bv.book_id, bv.chapter, bv.verse
        LIMIT ?
        ''',
        params,
      );
      return rows.map((r) => BibleVerseEntity.fromRow(r)).toList();
    } on SqliteException {
      // Malformed FTS5 query (unbalanced quotes, bare operators, etc.)
      return [];
    }
  }

  // ---------------------------------------------------------------------------
  // Translation queries
  // ---------------------------------------------------------------------------

  /// List distinct translations available in the database.
  ///
  /// Example return: ['KJV']
  List<String> getAvailableTranslations() {
    try {
      final rows = _db.select(
        'SELECT DISTINCT translation FROM bible_verses ORDER BY translation',
      );
      return rows.map((r) => r['translation'] as String).toList();
    } on SqliteException catch (e) {
      debugPrint('BibleRepository.getAvailableTranslations() failed: $e');
      return [];
    }
  }
}
