import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../../features/bible/domain/models/bible_reference.dart';
import '../database/sync_database.dart';

/// Service for fetching Bible verses from bible-api.com
/// with local caching via BibleCache table.
///
// Uses raw http.Client because this calls an external public API (bible-api.com)
// that doesn't require auth tokens. Retry logic is handled by _getWithRetry().
class BibleApiService {
  final SyncDatabase _db;
  final http.Client _httpClient;

  static const _baseUrl = 'https://bible-api.com';
  static const _uuid = Uuid();

  /// Supported public domain Bible versions
  static const supportedVersions = {
    'kjv': 'King James Version',
    'web': 'World English Bible',
    'asv': 'American Standard Version',
  };

  static const defaultVersion = 'kjv';

  BibleApiService(this._db, {http.Client? httpClient})
      : _httpClient = httpClient ?? http.Client();

  /// Fetch verse text, checking cache first
  ///
  /// Returns the verse text, or null if offline and not cached.
  Future<BibleVerseResult?> getVerse({
    required String book,
    required int chapter,
    required int verseStart,
    int? verseEnd,
    String version = defaultVersion,
  }) async {
    // Check cache first
    final cached = await _getCachedVerse(
      book: book,
      chapter: chapter,
      verseStart: verseStart,
      verseEnd: verseEnd,
      version: version,
    );

    if (cached != null) return cached;

    // Fetch from API
    try {
      final reference = _buildReference(book, chapter, verseStart, verseEnd);
      final url = Uri.parse('$_baseUrl/$reference?translation=$version');
      final response = await _getWithRetry(url);

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final text = _extractText(json);
        final verses = _extractVerses(json);
        final displayRef = _buildDisplayReference(
            book, chapter, verseStart, verseEnd, version);

        // Cache the result (concatenated text for lookup)
        await _cacheVerse(
          book: book,
          chapter: chapter,
          verseStart: verseStart,
          verseEnd: verseEnd,
          version: version,
          text: text,
          reference: displayRef,
        );

        return BibleVerseResult(
          book: book,
          chapter: chapter,
          verseStart: verseStart,
          verseEnd: verseEnd,
          version: version,
          text: text,
          verses: verses,
          reference: displayRef,
          pending: false,
          source: 'api',
        );
      }

      return null;
    } catch (_) {
      // Offline or error - return null (caller should set pending: true)
      return null;
    }
  }

  /// Retry wrapper for HTTP GET requests.
  ///
  /// Retries on 5xx responses and exceptions with exponential backoff.
  Future<http.Response> _getWithRetry(Uri url, {int maxRetries = 2}) async {
    for (var attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        final response = await _httpClient.get(url).timeout(
          const Duration(seconds: 10),
        );
        if (response.statusCode >= 500 && attempt < maxRetries) {
          await Future.delayed(Duration(seconds: attempt + 1));
          continue;
        }
        return response;
      } on Exception {
        if (attempt == maxRetries) rethrow;
        await Future.delayed(Duration(seconds: attempt + 1));
      }
    }
    throw Exception('Unreachable');
  }

  /// Build the API reference path (e.g., "john 3:16" or "john 3:16-18")
  String _buildReference(
      String book, int chapter, int verseStart, int? verseEnd) {
    final ref = '$book $chapter:$verseStart';
    if (verseEnd != null && verseEnd != verseStart) {
      return '$ref-$verseEnd';
    }
    return ref;
  }

  /// Build a display reference (e.g., "John 3:16 (KJV)")
  String _buildDisplayReference(
      String book, int chapter, int verseStart, int? verseEnd, String version) {
    final ref = '$book $chapter:$verseStart';
    final range =
        (verseEnd != null && verseEnd != verseStart) ? '-$verseEnd' : '';
    return '$ref$range (${version.toUpperCase()})';
  }

  /// Extract verse text from API response (concatenated string for cache)
  String _extractText(Map<String, dynamic> json) {
    if (json.containsKey('text')) {
      return (json['text'] as String).trim();
    }

    // Fallback: concatenate verses
    if (json.containsKey('verses')) {
      final verses = json['verses'] as List<dynamic>;
      return verses
          .map((v) => (v as Map<String, dynamic>)['text'] as String)
          .join(' ')
          .trim();
    }

    return '';
  }

  /// Extract individual verse texts from API response
  List<BibleVerseText> _extractVerses(Map<String, dynamic> json) {
    if (json.containsKey('verses')) {
      final verses = json['verses'] as List<dynamic>;
      return verses.map((v) {
        final map = v as Map<String, dynamic>;
        return BibleVerseText(
          verse: map['verse'] as int? ?? 1,
          content: (map['text'] as String? ?? '').trim(),
        );
      }).toList();
    }

    // Fallback: single text field
    final text = (json['text'] as String?)?.trim() ?? '';
    if (text.isEmpty) return [];
    return [BibleVerseText(verse: 1, content: text)];
  }

  /// Check cache for a verse
  Future<BibleVerseResult?> _getCachedVerse({
    required String book,
    required int chapter,
    required int verseStart,
    int? verseEnd,
    required String version,
  }) async {
    final query = _db.select(_db.bibleCache)
      ..where((t) =>
          t.book.equals(book) &
          t.chapter.equals(chapter) &
          t.verseStart.equals(verseStart) &
          t.version.equals(version));

    if (verseEnd != null) {
      query.where((t) => t.verseEnd.equals(verseEnd));
    } else {
      query.where((t) => t.verseEnd.isNull());
    }

    final results = await query.get();
    if (results.isEmpty) return null;

    final row = results.first;
    // Cache stores concatenated text — construct single-entry verses list
    final cachedVerses = row.verseText.isNotEmpty
        ? [BibleVerseText(verse: row.verseStart, content: row.verseText)]
        : <BibleVerseText>[];
    return BibleVerseResult(
      book: row.book,
      chapter: row.chapter,
      verseStart: row.verseStart,
      verseEnd: row.verseEnd,
      version: row.version,
      text: row.verseText,
      verses: cachedVerses,
      reference: row.reference,
      pending: false,
      source: 'local',
    );
  }

  /// Cache a verse result
  Future<void> _cacheVerse({
    required String book,
    required int chapter,
    required int verseStart,
    int? verseEnd,
    required String version,
    required String text,
    required String reference,
  }) async {
    await _db.into(_db.bibleCache).insertOnConflictUpdate(
          BibleCacheCompanion.insert(
            id: _uuid.v4(),
            book: book,
            chapter: chapter,
            verseStart: verseStart,
            verseEnd: Value(verseEnd),
            version: version,
            verseText: text,
            reference: reference,
            fetchedAt: DateTime.now().millisecondsSinceEpoch,
          ),
        );
  }

  void dispose() {
    _httpClient.close();
  }
}

/// Result of a Bible verse lookup
class BibleVerseResult {
  final String book;
  final int chapter;
  final int verseStart;
  final int? verseEnd;
  final String version;

  /// Concatenated text (for cache compatibility)
  final String text;

  /// Individual verse texts (from API parsing)
  final List<BibleVerseText> verses;

  final String reference;
  final bool pending;

  /// "local" (from cache) or "api" (freshly fetched)
  final String source;

  const BibleVerseResult({
    required this.book,
    required this.chapter,
    required this.verseStart,
    this.verseEnd,
    required this.version,
    required this.text,
    this.verses = const [],
    required this.reference,
    required this.pending,
    this.source = 'api',
  });

  Map<String, dynamic> toJson() {
    return {
      'book': book,
      'chapter': chapter,
      'verseStart': verseStart,
      if (verseEnd != null) 'verseEnd': verseEnd,
      'version': version,
      'text': text,
      'verses': verses.map((v) => v.toJson()).toList(),
      'reference': reference,
      'pending': pending,
      'source': source,
    };
  }

  factory BibleVerseResult.fromJson(Map<String, dynamic> json) {
    return BibleVerseResult(
      book: json['book'] as String,
      chapter: json['chapter'] as int,
      verseStart: json['verseStart'] as int,
      verseEnd: json['verseEnd'] as int?,
      version: json['version'] as String? ?? 'kjv',
      text: json['text'] as String? ?? '',
      verses: (json['verses'] as List<dynamic>?)
              ?.map((v) => BibleVerseText.fromJson(v as Map<String, dynamic>))
              .toList() ??
          [],
      reference: json['reference'] as String? ?? '',
      pending: json['pending'] as bool? ?? false,
      source: json['source'] as String? ?? 'api',
    );
  }
}
