// One parser feeds both the tint in the editor and the tag on the note. If the
// two ever disagreed it would look like a word highlighted as a tag that was
// never saved as one, so the rules live here and are pinned.

import 'package:flutter_test/flutter_test.dart';
import 'package:notify/features/notes/domain/services/inline_tag_parser.dart';

void main() {
  Set<String> names(String text) => InlineTagParser.names(text);

  group('what counts as a tag', () {
    test('a plain #word', () {
      expect(names('trusting in #faith today'), {'faith'});
    });

    test('at the very start of the text', () {
      expect(names('#faith is the substance'), {'faith'});
    });

    test('after a newline', () {
      expect(names('line one\n#faith'), {'faith'});
    });

    test('several in one block', () {
      expect(names('#faith and #grace and #hope'), {'faith', 'grace', 'hope'});
    });

    test('digits, underscores and hyphens are part of the word', () {
      expect(names('#psalm23 #new_life #well-being'),
          {'psalm23', 'new_life', 'well-being'});
    });

    test('non-Latin scripts', () {
      expect(names('#благодать'), {'благодать'});
    });
  });

  group('what does not', () {
    test('a # attached to a preceding word, like a URL fragment', () {
      expect(names('example.com#section'), isEmpty);
      expect(names('C#'), isEmpty);
    });

    test('a bare # with nothing after it', () {
      expect(names('what # even'), isEmpty);
    });

    test('text with no # at all', () {
      expect(names('no tags here'), isEmpty);
    });
  });

  group('boundaries', () {
    test('trailing punctuation is not part of the tag', () {
      expect(names('I have #faith.'), {'faith'});
      expect(names('#faith, #grace!'), {'faith', 'grace'});
    });

    test('the span covers the # and the word, and nothing else', () {
      final tags = InlineTagParser.parse('ab #faith.');
      expect(tags, hasLength(1));
      expect(tags.single.start, 3);
      expect(tags.single.end, 9, reason: 'the full stop must stay outside');
      expect('ab #faith.'.substring(tags.single.start, tags.single.end),
          '#faith');
    });
  });

  group('normalising', () {
    test('the name is lowercased, matching what the repository stores', () {
      expect(names('#Faith #FAITH #faith'), {'faith'});
    });

    test('the same tag twice in one block is one name', () {
      expect(names('#faith and more #faith'), {'faith'});
    });
  });
}
