// Song search ranking: title first, then tags weighted by how strongly each
// song carries them, then lyrics. The tiers are compared in turn, never added
// together, so these tests pin the order of whole tiers as well as each rule.

import 'package:flutter_test/flutter_test.dart';
import 'package:notify/core/sync/models/song_model.dart';
import 'package:notify/features/songs/domain/song_search_ranker.dart';

SongModel _song(String id, String title, {String lyrics = ''}) => SongModel(
      id: id,
      userId: 'u',
      title: title,
      lyrics: lyrics,
      chords: '',
      language: 'English',
      preview: '',
      tags: '',
      hasChords: false,
      isFavorite: false,
      updatedAt: 0,
      version: 1,
      deleted: 0,
      createdAt: 0,
    );

SongTagHit _tag(String name, int weight) =>
    SongTagHit(tagId: 'tag-$name', name: name, weight: weight);

List<String> _titles(List<RankedSong> r) => [for (final x in r) x.song.title];

void main() {
  List<RankedSong> rank(List<SongModel> songs, String query,
          {Map<String, List<SongTagHit>> tags = const {},
          Set<String> selected = const {}}) =>
      SongSearchRanker.rank(
          songs: songs, tagsBySong: tags, query: query, selectedTagIds: selected);

  group('title tier', () {
    test('exact > starts with > word starts with > contains', () {
      final songs = [
        _song('d', 'Disgraceful'), // contains: 2
        _song('c', 'Amazing Grace'), // a word starts with: 3
        _song('b', 'Grace Alone'), // starts with: 4
        _song('a', 'Grace'), // exact: 5
      ];
      expect(_titles(rank(songs, 'grace')),
          ['Grace', 'Grace Alone', 'Amazing Grace', 'Disgraceful']);
    });

    test('every query word in the title, apart, is the weakest title match', () {
      final r = rank([_song('x', 'Grace that is amazing'), _song('y', 'Amazing Grace')],
          'amazing grace');
      expect(_titles(r), ['Amazing Grace', 'Grace that is amazing']);
      expect(r.last.titleScore, 1);
    });

    test('"every word" wants word starts, not letters inside words', () {
      // A title outranks every tag match, so a loose title hit is costly.
      final r = rank([_song('a', 'Godly This', lyrics: 'this godly line')], 'god is');
      expect(r, isEmpty,
          reason: '"god" and "is" are inside words here, not words themselves');
    });

    test('an edited song is re-read, not served from the cache', () {
      final before = _song('a', 'Old Title');
      expect(rank([before], 'old'), hasLength(1));
      final after = SongModel(
        id: 'a', userId: 'u', title: 'New Title', lyrics: '', chords: '',
        language: 'English', preview: '', tags: '', hasChords: false,
        isFavorite: false, updatedAt: 1, version: 2, deleted: 0, createdAt: 0,
      );
      expect(rank([after], 'old'), isEmpty);
      expect(rank([after], 'new').single.titleScore, 4);
    });

    test('ignores case and punctuation', () {
      final r = rank([_song('a', 'Blessed Be (Your Name)!')], 'blessed be your name');
      expect(r.single.titleScore, 5);
    });
  });

  test('any title match outranks any tag score', () {
    final songs = [
      // Title holds every word but scores only 1.
      _song('t', 'Holy is the spirit'),
      // No title match, but a central tag that is the whole query: 3 × 3 = 9.
      _song('g', 'Fire Fall Down'),
    ];
    final r = rank(songs, 'holy spirit', tags: {
      'g': [_tag('holy spirit', 3)],
    });
    expect(_titles(r), ['Holy is the spirit', 'Fire Fall Down']);
    expect(r[1].tagScore, 9);
  });

  group('tag tier', () {
    test('scales with weight, then with how well the tag matches', () {
      final songs = [
        _song('w1', 'One'),
        _song('w3', 'Two'),
        _song('w2', 'Three'),
      ];
      final r = rank(songs, 'grace', tags: {
        'w1': [_tag('grace', 1)],
        'w3': [_tag('grace', 3)],
        'w2': [_tag('grace', 2)],
      });
      expect(_titles(r), ['Two', 'Three', 'One']);
      expect([for (final x in r) x.tagScore], [9, 6, 3]);
    });

    test('a tag named inside a longer query counts, as a whole phrase', () {
      final r = rank([_song('a', 'Rain Down')], 'holy spirit fire', tags: {
        'a': [_tag('holy spirit', 3), _tag('fire', 1), _tag('spirit', 2)],
      });
      // holy spirit 3×2, fire 1×2, spirit 2×2
      expect(r.single.tagScore, 12);
    });

    test('a tag is found while its name is still being typed', () {
      final songs = [_song('a', 'Rain Down')];
      final tags = {'a': [_tag('grace', 2)]};
      expect(rank(songs, 'gra', tags: tags).single.tagScore, 2);
      expect(rank(songs, 'gr', tags: tags), isEmpty,
          reason: 'two letters match too much to be useful');
    });

    test('a song found only by its tag is included', () {
      final r = rank([_song('a', 'Your Love Never Fails', lyrics: 'nothing')],
          'grace', tags: {'a': [_tag('grace', 2)]});
      expect(r.single.tagScore, 6);
    });
  });

  test('lyrics come last, and a lyrics-only match is still a result', () {
    final songs = [
      _song('l', 'Ten Thousand Reasons', lyrics: 'bless the Lord O my soul'),
      _song('t', 'Unrelated', lyrics: 'other words'),
      _song('g', 'Also Unrelated'),
    ];
    final r = rank(songs, 'my soul', tags: {
      'g': [_tag('my soul', 1)],
    });
    expect(_titles(r), ['Also Unrelated', 'Ten Thousand Reasons'],
        reason: 'a tag match (tier 2) beats a lyrics match (tier 3)');
    expect(r.last.lyricsScore, 2);
  });

  test('songs that match nothing are dropped when there is a query', () {
    expect(rank([_song('a', 'Amazing Grace')], 'zzz'), isEmpty);
  });

  test('ties break by title, ignoring case', () {
    // Case-sensitive order would put every capitalised title first.
    final songs = [_song('1', 'zion'), _song('2', 'Bless'), _song('3', 'amen')];
    expect(_titles(rank(songs, '')), ['amen', 'Bless', 'zion']);
  });

  group('tag filter', () {
    test('orders by the weight carried on the chosen tags, then by count', () {
      final songs = [
        _song('a', 'A light'),
        _song('b', 'B strong'),
        _song('c', 'C two weak'),
        _song('d', 'D none'),
      ];
      final tags = {
        'a': [_tag('grace', 1)],
        'b': [_tag('grace', 3)],
        'c': [_tag('grace', 2), _tag('healing', 1)],
        'd': [_tag('peace', 3)],
      };
      final r = rank(songs, '',
          tags: tags, selected: {'tag-grace', 'tag-healing'});
      // C: 2 + 1 = 3 over two tags; B: 3 on one. Equal weight, so the song
      // carrying more of the chosen tags comes first. D has none: dropped by
      // the SQL filter in the app, kept here (the ranker only orders).
      expect(_titles(r).take(3), ['C two weak', 'B strong', 'A light']);
      expect([r[0].filterWeight, r[0].filterCount], [3, 2]);
      expect([r[1].filterWeight, r[1].filterCount], [3, 1]);
    });

    test('with a query, the text tiers come before the filter weight', () {
      final songs = [_song('a', 'Grace Alone'), _song('b', 'Something')];
      final r = rank(songs, 'grace',
          tags: {
            'a': [_tag('healing', 1)],
            'b': [_tag('healing', 3), _tag('grace', 1)],
          },
          selected: {'tag-healing'});
      expect(_titles(r), ['Grace Alone', 'Something']);
    });
  });

  test('matched tags are listed strongest first', () {
    final r = rank([_song('a', 'X')], 'grace', tags: {
      'a': [_tag('gracefulness', 3), _tag('grace', 2), _tag('peace', 3)],
    });
    // grace 2×3 = 6 beats gracefulness 3×1 = 3; peace did not match
    expect(r.single.matchedTagIds, ['tag-grace', 'tag-gracefulness']);
  });

  group('Telugu, Hindi and accents', () {
    test('Telugu words keep their vowel signs', () {
      final r = rank([_song('a', 'యేసయ్యా నా ప్రాణం')], 'నా ప్రాణం');
      expect(r.single.titleScore, 3,
          reason: 'a word starts with the query; without combining marks the '
              'words would split apart and this would not match');
    });

    test('a syllable inside a word is not the start of a word', () {
      // "రా" is the middle of "ప్రాణం". Without combining marks in the word
      // pattern, the vowel signs become gaps, the word falls apart into
      // letters, and "రా" would look like the start of one.
      final r = rank([_song('a', 'ప్రాణం')], 'రా');
      expect(r.single.titleScore, 2);
    });

    test('Hindi', () {
      final r = rank([_song('a', 'Yeshu Mera Tera Sabka', lyrics: 'यीशु मेरा राजा')],
          'मेरा राजा');
      expect(r.single.lyricsScore, 2);
    });

    test('case folds beyond ASCII', () {
      expect(rank([_song('a', 'Élohim')], 'élohim').single.titleScore, 5);
    });
  });
}
