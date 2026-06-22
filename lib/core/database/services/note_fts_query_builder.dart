/// Builds safe FTS5 MATCH expressions from raw user input for note search.
///
/// Same pattern as [BibleFtsQueryBuilder]:
/// - Strips FTS5 special characters to prevent injection
/// - Supports quoted phrases: "sermon notes" → `"sermon notes"`
/// - AND logic between terms (all terms must match)
/// - Prefix matching on individual words via trailing *
/// - Minimum 2-character validation per term
/// - Quotes FTS5 keywords (AND, OR, NOT, NEAR) used as search terms
class NoteFtsQueryBuilder {
  NoteFtsQueryBuilder._();

  /// FTS5 keywords that must be quoted when used as literal search terms.
  static const _ftsKeywords = {'and', 'or', 'not', 'near'};

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
      final terms = remaining
          .split(RegExp(r'\s+'))
          .map(_sanitizeToken)
          .where((t) => t.length >= 2)
          .map(_formatTerm)
          .toList();
      parts.addAll(terms);
    }

    if (parts.isEmpty) return null;
    return parts.join(' AND ');
  }

  /// Remove all characters that could act as FTS5 operators or cause
  /// query injection. Keeps only Unicode letters, numbers, and apostrophes.
  static String _sanitizeToken(String token) {
    return token.replaceAll(RegExp(r"[^\p{L}\p{N}']", unicode: true), '');
  }

  /// Format a single sanitized term for FTS5.
  ///
  /// FTS5 keywords are double-quoted so they are treated as literal
  /// search terms rather than operators. All other terms get a trailing
  /// `*` for prefix matching.
  static String _formatTerm(String word) {
    if (_ftsKeywords.contains(word)) {
      return '"$word"*';
    }
    return '$word*';
  }
}
