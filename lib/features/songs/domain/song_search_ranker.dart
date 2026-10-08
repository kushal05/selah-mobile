import '../../../core/sync/models/song_model.dart';

/// One live tag on a song, as the ranker sees it.
class SongTagHit {
  final String tagId;
  final String name;

  /// 3 a central theme, 2 a clear theme, 1 present but minor.
  final int weight;

  const SongTagHit({required this.tagId, required this.name, required this.weight});
}

/// A song in a ranked result, with the scores that placed it.
class RankedSong {
  final SongModel song;

  /// Tier 1: how the title matches the query (0-5).
  final int titleScore;

  /// Tier 2: Σ weight × match quality over the song's matching tags.
  final int tagScore;

  /// Tier 3: how the lyrics match the query (0-2).
  final int lyricsScore;

  /// Σ weight of the song's links to the tags chosen in the filter.
  final int filterWeight;

  /// How many of the chosen tags the song carries.
  final int filterCount;

  /// Tags that matched the query or the filter, strongest first, so a result
  /// card can show why the song is there.
  final List<String> matchedTagIds;

  const RankedSong({
    required this.song,
    this.titleScore = 0,
    this.tagScore = 0,
    this.lyricsScore = 0,
    this.filterWeight = 0,
    this.filterCount = 0,
    this.matchedTagIds = const [],
  });
}

/// Orders song search results: title first, then tags weighted by how
/// strongly each song carries them, then lyrics.
///
/// The tiers are compared in turn, never added together, so no number of tag
/// or lyric matches lifts a song above one whose title matches. Ranking only
/// orders: the hard filters (key, language, songbook, tags) are applied before
/// the songs get here.
///
/// In Dart rather than SQL because SQLite's lower() folds only ASCII, and its
/// LIKE knows nothing of word boundaries in Telugu or Hindi.
class SongSearchRanker {
  SongSearchRanker._();

  // Letters, digits and combining marks. The marks matter: Telugu and Hindi
  // vowel signs are marks, and without them every word splits in pieces.
  static final _word = RegExp(r'[\p{L}\p{M}\p{N}]+', unicode: true);

  /// Lowercased words joined by single spaces; punctuation and line breaks
  /// become word gaps.
  static String normalise(String text) =>
      _word.allMatches(text.toLowerCase()).map((m) => m.group(0)).join(' ');

  // Normalising every song's lyrics was nearly all of a search's cost (about
  // 50ms over 652 songs, on the UI isolate, at every pause in typing). Songs
  // rarely change between keystrokes, so keep the result until they do.
  //
  // An entry is valid while the song's text is the text it was made from.
  // Keyed on content rather than updatedAt, so no path that changes a song
  // without bumping updatedAt can serve stale text; comparing the strings
  // costs far less than normalising them again.
  static final _songText =
      <String, ({String rawTitle, String rawLyrics, String title, String lyrics})>{};
  static final _tagText = <String, String>{};
  static const _cacheLimit = 5000;

  static ({String title, String lyrics}) _textOf(SongModel song) {
    final c = _songText[song.id];
    if (c != null && c.rawTitle == song.title && c.rawLyrics == song.lyrics) {
      return (title: c.title, lyrics: c.lyrics);
    }
    if (_songText.length >= _cacheLimit) _songText.clear();
    final title = normalise(song.title), lyrics = normalise(song.lyrics);
    _songText[song.id] =
        (rawTitle: song.title, rawLyrics: song.lyrics, title: title, lyrics: lyrics);
    return (title: title, lyrics: lyrics);
  }

  static String _tagName(String name) {
    final cached = _tagText[name];
    if (cached != null) return cached;
    if (_tagText.length >= _cacheLimit) _tagText.clear();
    return _tagText[name] = normalise(name);
  }

  /// Ranks [songs] for [query] (may be empty) and the tag filter
  /// [selectedTagIds]. [tagsBySong] holds each song's live tags. With a query,
  /// songs matching nothing are dropped; without one, every song is kept.
  static List<RankedSong> rank({
    required List<SongModel> songs,
    required Map<String, List<SongTagHit>> tagsBySong,
    String query = '',
    Set<String> selectedTagIds = const {},
  }) {
    final q = normalise(query);
    final qWords = q.isEmpty ? const <String>[] : q.split(' ');
    final ranked = <RankedSong>[];

    for (final song in songs) {
      final tags = tagsBySong[song.id] ?? const <SongTagHit>[];
      final strength = <String, int>{}; // tagId -> contribution, for ordering

      var filterWeight = 0;
      var filterCount = 0;
      if (selectedTagIds.isNotEmpty) {
        final seen = <String>{};
        for (final t in tags) {
          if (selectedTagIds.contains(t.tagId) && seen.add(t.tagId)) {
            filterWeight += t.weight;
            filterCount++;
            strength[t.tagId] = (strength[t.tagId] ?? 0) + t.weight;
          }
        }
      }

      var titleScore = 0, tagScore = 0, lyricsScore = 0;
      if (q.isNotEmpty) {
        final text = _textOf(song);
        titleScore = _titleScore(text.title, q, qWords);
        final seen = <String>{};
        for (final t in tags) {
          if (!seen.add(t.tagId)) continue;
          final quality = _tagQuality(_tagName(t.name), q);
          if (quality > 0) {
            tagScore += t.weight * quality;
            strength[t.tagId] = (strength[t.tagId] ?? 0) + t.weight * quality;
          }
        }
        lyricsScore = _lyricsScore(text.lyrics, q, qWords);
        if (titleScore == 0 && tagScore == 0 && lyricsScore == 0) continue;
      }

      final matched = strength.keys.toList()
        ..sort((a, b) => strength[b]!.compareTo(strength[a]!));
      ranked.add(RankedSong(
        song: song,
        titleScore: titleScore,
        tagScore: tagScore,
        lyricsScore: lyricsScore,
        filterWeight: filterWeight,
        filterCount: filterCount,
        matchedTagIds: matched,
      ));
    }

    ranked.sort(_compare);
    return ranked;
  }

  static int _compare(RankedSong a, RankedSong b) {
    for (final c in [
      b.titleScore.compareTo(a.titleScore),
      b.tagScore.compareTo(a.tagScore),
      b.lyricsScore.compareTo(a.lyricsScore),
      b.filterWeight.compareTo(a.filterWeight),
      b.filterCount.compareTo(a.filterCount),
      a.song.title.toLowerCase().compareTo(b.song.title.toLowerCase()),
      a.song.title.compareTo(b.song.title),
      a.song.id.compareTo(b.song.id),
    ]) {
      if (c != 0) return c;
    }
    return 0;
  }

  /// 5 exact · 4 title starts with the query · 3 a title word starts with it ·
  /// 2 contains it · 1 every query word starts a word of the title · 0 none.
  ///
  /// The last rule wants word starts, not substrings: a title outranks every
  /// tag match, so "god is" must not lift a title like "Godly This" above
  /// songs that carry the theme.
  static int _titleScore(String title, String q, List<String> qWords) {
    if (title.isEmpty) return 0;
    if (title == q) return 5;
    if (title.startsWith(q)) return 4;
    if (' $title'.contains(' $q')) return 3;
    if (title.contains(q)) return 2;
    if (qWords.length > 1 && qWords.every((w) => ' $title'.contains(' $w'))) {
      return 1;
    }
    return 0;
  }

  /// 3 the tag is the query · 2 the query holds the tag as a whole phrase
  /// ("holy spirit fire" holds "holy spirit"; a query word equal to a one-word
  /// tag counts too) · 1 the tag starts with the query, once it is three
  /// characters long (typing "gra" finds grace) · 0 none.
  static int _tagQuality(String tag, String q) {
    if (tag.isEmpty) return 0;
    if (tag == q) return 3;
    if (' $q '.contains(' $tag ')) return 2;
    if (q.length >= 3 && tag.startsWith(q)) return 1;
    return 0;
  }

  /// 2 the lyrics contain the query as a phrase · 1 every query word starts a
  /// word somewhere in them (word starts, as for titles: "is" is inside
  /// nearly every song).
  static int _lyricsScore(String lyrics, String q, List<String> qWords) {
    if (lyrics.isEmpty) return 0;
    if (lyrics.contains(q)) return 2;
    if (qWords.length > 1 && qWords.every((w) => ' $lyrics'.contains(' $w'))) {
      return 1;
    }
    return 0;
  }
}
