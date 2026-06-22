import 'package:flutter/foundation.dart';

import '../../bible/data/bible_database_service.dart';
import '../domain/models/bible_search_result.dart';
import 'bible_fts_query_builder.dart';
import 'bible_search_isolate.dart';

/// Search service for Bible verses using SQLite FTS5.
///
/// Queries the pre-populated Bible database managed by [BibleDatabaseService].
/// This service is COMPLETELY SEPARATE from global search and song search.
///
/// Design:
/// - Uses the existing `bible.db` (read-only asset database)
/// - Adds FTS5 highlight() for match highlighting
/// - Adds testament / book / translation filter support
/// - Sanitises user input via [BibleFtsQueryBuilder]
/// - All SQL runs in [BibleSearchIsolate] so multi-word FTS prefix queries
///   never block the UI thread (package:sqlite3 is sync)
class BibleSearchService {
  final BibleDatabaseService _dbService;
  final BibleSearchIsolate _isolate;

  Future<void>? _startFuture;

  BibleSearchService(this._dbService) : _isolate = BibleSearchIsolate();

  /// Whether the Bible database is ready for queries.
  bool get isAvailable => _dbService.isOpen;

  /// Spawn the worker isolate on first use. Subsequent calls reuse the
  /// existing worker. The future completes once the isolate has signalled
  /// that it has opened its own connection to the Bible DB.
  ///
  /// On failure the cached future is cleared so the next call can retry —
  /// otherwise a one-off path lookup or spawn error would permanently
  /// disable Bible search until the provider is recreated.
  Future<void> _ensureStarted() {
    final existing = _startFuture;
    if (existing != null) return existing;
    final future = _dbService.dbPath().then(_isolate.start);
    _startFuture = future;
    future.catchError((_) {
      if (identical(_startFuture, future)) _startFuture = null;
    });
    return future;
  }

  /// Search Bible verse text using FTS5.
  ///
  /// Returns up to [limit] results ordered by FTS5 BM25 relevance.
  /// The [query] is sanitised and converted to a safe FTS5 MATCH expression.
  /// Optional [testament], [bookId], and [translation] narrow the results.
  ///
  /// Returns an empty list if the database is not open, the query is too
  /// short, or no verses match.
  Future<List<BibleSearchResult>> search({
    required String query,
    Set<int> testaments = const {},
    Set<int> bookIds = const {},
    Set<String> translations = const {},
    BibleSearchSortOption sortBy = BibleSearchSortOption.frequency,
    int limit = 50,
    int offset = 0,
  }) async {
    if (!_dbService.isOpen) return [];

    final ftsQuery = BibleFtsQueryBuilder.build(query);
    if (ftsQuery == null) return [];

    final orderClause = switch (sortBy) {
      BibleSearchSortOption.frequency => 'ORDER BY rank',
      BibleSearchSortOption.books => 'ORDER BY bv.book_id, bv.chapter, bv.verse',
    };

    try {
      await _ensureStarted();
      return await _isolate.search(
        ftsQuery: ftsQuery,
        testaments: testaments,
        bookIds: bookIds,
        translations: translations,
        orderClause: orderClause,
        limit: limit,
        offset: offset,
        hlOpen: BibleSearchResult.hlOpen,
        hlClose: BibleSearchResult.hlClose,
      );
    } catch (e) {
      debugPrint('BibleSearchService.search() failed: $e');
      return [];
    }
  }

  /// Total number of verses in the Bible database.
  Future<int> getVerseCount() async {
    if (!_dbService.isOpen) return 0;
    try {
      await _ensureStarted();
      return await _isolate.getVerseCount();
    } catch (e) {
      debugPrint('BibleSearchService.getVerseCount() failed: $e');
      return 0;
    }
  }

  /// Tear down the worker isolate. Called when the owning provider is
  /// disposed.
  void dispose() {
    _isolate.dispose();
  }
}
