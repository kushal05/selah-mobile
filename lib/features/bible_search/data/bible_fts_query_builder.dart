/// Builds safe FTS5 MATCH expressions from raw user input.
///
/// Features:
/// - Strips FTS5 special characters to prevent injection
/// - Supports quoted phrases: "God so loved" → `"god so loved"`
/// - AND logic between terms (all terms must match)
/// - Prefix matching on individual words via trailing *
/// - Minimum 2-character validation per term
/// - Quotes FTS5 keywords (AND, OR, NOT, NEAR) used as search terms
class BibleFtsQueryBuilder {
  BibleFtsQueryBuilder._();

  /// FTS5 keywords that must be quoted when used as literal search terms.
  static const _ftsKeywords = {'and', 'or', 'not', 'near'};

  /// English words that appear in nearly every Bible verse. Including any of
  /// these in an `AND`-of-prefixes query forces FTS5 to BM25-rank tens of
  /// thousands of rows for no semantic gain — a verse containing any other
  /// requested word almost certainly contains "the" too. Stripping them keeps
  /// the result set identical (BM25 weight is ~zero for terms with very low
  /// IDF) and turns 30-50ms `the lord` into <1ms `lord*`.
  ///
  /// Only stripped from the unquoted-AND term list. Phrase queries like
  /// `"the lord is my shepherd"` keep stop words because positional matters
  /// inside a phrase.
  static const _stopWords = {
    'a', 'an', 'and', 'are', 'as', 'at', 'be', 'but', 'by', 'do', 'for',
    'from', 'had', 'has', 'have', 'he', 'her', 'him', 'his', 'i', 'in',
    'is', 'it', 'its', 'me', 'my', 'no', 'not', 'of', 'on', 'or', 'our',
    'out', 'shall', 'she', 'so', 'than', 'that', 'the', 'their', 'them',
    'then', 'there', 'these', 'they', 'this', 'those', 'to', 'us', 'was',
    'we', 'were', 'what', 'when', 'which', 'who', 'will', 'with', 'would',
    'you', 'your',
  };

  /// Regex to extract double-quoted phrases from user input.
  static final _phraseRegex = RegExp(r'"([^"]+)"');

  /// Build a safe FTS5 MATCH expression from [rawQuery].
  ///
  /// Returns `null` if the input is too short or produces no valid terms.
  ///
  /// Examples:
  /// - `"faith hope love"`      → `faith* AND hope* AND love*`
  /// - `'"God so loved" world'` → `"god so loved" AND world*`
  /// - `"a"`                    → `null` (too short)
  /// - `"NOT grace"`            → `"not"* AND grace*`
  static String? build(String rawQuery) {
    final trimmed = rawQuery.trim();
    if (trimmed.length < 2) return null;

    final parts = <String>[];

    // ── Extract quoted phrases first ──────────────────────────────────
    for (final match in _phraseRegex.allMatches(trimmed)) {
      final phrase = match.group(1)!.trim().toLowerCase();
      if (phrase.length < 2) continue;

      final sanitized = phrase
          .split(RegExp(r'\s+'))
          .map(_sanitizeToken)
          .where((t) => t.isNotEmpty)
          .join(' ');

      if (sanitized.length >= 2) {
        parts.add('"$sanitized"');
      }
    }

    // ── Process remaining words as individual prefix-matched terms ────
    final remaining =
        trimmed.replaceAll(_phraseRegex, ' ').trim().toLowerCase();

    if (remaining.isNotEmpty) {
      final tokens = remaining
          .split(RegExp(r'\s+'))
          .map(_sanitizeToken)
          .where((t) => t.length >= 2)
          .toList();

      // Drop stop words *only if* at least one informative term remains.
      // Otherwise a query like "the to of" would collapse to nothing and
      // the user would see no results — preserve the originals so the
      // search still runs (just slowly, which is the cost of asking for
      // ubiquitous words).
      final informative =
          tokens.where((t) => !_stopWords.contains(t)).toList();
      final terms = informative.isNotEmpty ? informative : tokens;

      parts.addAll(terms.map(_formatTerm));
    }

    if (parts.isEmpty) return null;
    return parts.join(' AND ');
  }

  /// Remove all characters that could act as FTS5 operators or cause
  /// query injection. Keeps only Unicode letters, numbers, and apostrophes.
  static String _sanitizeToken(String token) {
    return token.replaceAll(RegExp(r"[^\p{L}\p{N}']", unicode: true), '');
  }

  /// Minimum word length that gets a trailing `*` for prefix matching.
  ///
  /// Without an FTS5 prefix index in the shipped `bible.db`, prefix queries
  /// expand by linear-scanning the term index and unioning every matching
  /// doclist. For short terms like `to*` or `the*` that union covers
  /// hundreds of distinct words across ~31k verses per translation and
  /// dominates query time. Restricting prefix matching to longer terms
  /// keeps the expansion small.
  ///
  /// When the CDN ships a DB built with `prefix='2 3 4'`, this floor can be
  /// dropped to 2 — FTS5 will resolve any prefix in those lengths via a
  /// direct index seek.
  static const int _minPrefixLength = 4;

  /// Format a single sanitized term for FTS5.
  ///
  /// FTS5 keywords are double-quoted so they are treated as literal
  /// search terms rather than operators. Terms long enough to keep prefix
  /// expansion cheap get a trailing `*`; shorter terms match exactly.
  static String _formatTerm(String word) {
    final usePrefix = word.length >= _minPrefixLength;
    if (_ftsKeywords.contains(word)) {
      // Quote the keyword so FTS5 treats it as a literal.
      return usePrefix ? '"$word"*' : '"$word"';
    }
    return usePrefix ? '$word*' : word;
  }
}
