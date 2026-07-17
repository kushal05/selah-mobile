import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:notify/features/bible/domain/models/bible_reference.dart';

/// [BibleReference.tryParse] is the single place that turns a bible block's
/// JSON payload into readable text. Four consumers depend on it — FTS indexing,
/// PDF export, version diffs and markdown export — so a false negative shows
/// users raw JSON, and a false positive mangles their real text.
void main() {
  String jsonOf({
    String book = 'John',
    int chapter = 3,
    List<int> verses = const [16],
    String version = 'kjv',
    List<BibleVerseText> text = const [],
  }) =>
      jsonEncode(BibleReference(
        reference: BibleVerseReference(
          book: book,
          chapter: chapter,
          verses: verses,
          version: version,
        ),
        text: text,
        source: 'local',
        insertedAt: 1,
        display: const BibleVerseDisplay(),
        pending: false,
      ).toJson());

  group('tryParse accepts real references', () {
    test('round-trips a reference payload', () {
      final ref = BibleReference.tryParse(jsonOf());
      expect(ref, isNotNull);
      expect(ref!.reference.book, 'John');
      expect(ref.reference.chapter, 3);
    });

    test('plainSummary is readable and JSON-free', () {
      final summary = BibleReference.tryParse(jsonOf(text: const [
        BibleVerseText(verse: 16, content: 'For God so loved the world'),
      ]))!
          .plainSummary;

      expect(summary, contains('John 3:16'));
      expect(summary, contains('For God so loved the world'));
      expect(summary, isNot(contains('{')));
      expect(summary, isNot(contains('insertedAt')));
    });

    test('plainSummary without verse text is just the reference', () {
      expect(BibleReference.tryParse(jsonOf())!.plainSummary, 'John 3:16 (KJV)');
    });
  });

  group('tryParse rejects everything else', () {
    test('ordinary prose', () {
      expect(BibleReference.tryParse('Just a note about John 3:16'), isNull);
      expect(BibleReference.tryParse(''), isNull);
      expect(BibleReference.tryParse('not json'), isNull);
    });

    test('prose that mentions reference in braces/quotes', () {
      expect(
        BibleReference.tryParse('See the {reference} — "reference" material'),
        isNull,
      );
    });

    test('unrelated JSON that merely has a reference key', () {
      expect(
        BibleReference.tryParse('{"reference": {"id": 7}, "note": "payload"}'),
        isNull,
      );
      // Empty/missing book must not produce a bogus " 1:1" reference.
      expect(BibleReference.tryParse('{"reference": {"book": ""}}'), isNull);
      expect(BibleReference.tryParse('{"reference": "John 3:16"}'), isNull);
    });

    test('a JSON array is not a reference', () {
      expect(BibleReference.tryParse('[{"reference": 1}]'), isNull);
    });
  });
}
