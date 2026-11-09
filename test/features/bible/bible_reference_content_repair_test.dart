// A Bible card's content is a JSON string. An earlier backspace bug appended
// the text of the line below it ("Tail"), so the string no longer parsed and
// the card fell back to BibleReference.empty() (no book, 1:1, KJV). The
// reference data is still in the string, in front of the stray text.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:notify/features/bible/domain/models/bible_reference.dart';

BibleReference _john316() => const BibleReference(
      reference: BibleVerseReference(
          book: 'John', chapter: 3, verses: [16], version: 'nasb'),
      text: [],
    );

void main() {
  final json = jsonEncode(_john316().toJson());

  test('valid content parses as before', () {
    final ref = BibleReference.tryParseContent(json)!;
    expect(ref.reference.book, 'John');
    expect(ref.reference.version, 'nasb');
  });

  test('content with text appended is recovered, not replaced by defaults', () {
    final ref = BibleReference.tryParseContent('${json}Tail')!;
    expect(ref.reference.book, 'John');
    expect(ref.reference.chapter, 3);
    expect(ref.reference.verses, [16]);
    expect(ref.reference.version, 'nasb');
  });

  test('splitContent returns the reference JSON and the stray text', () {
    final parts = BibleReference.splitContent('${json}Tail {with} braces')!;
    expect(parts.json, json);
    expect(parts.trailing, 'Tail {with} braces');
  });

  test('braces inside strings do not end the object early', () {
    const tricky = '{"reference":{"book":"A}B","chapter":1,"verses":[1],'
        '"version":"kjv"},"text":[]}rest';
    final parts = BibleReference.splitContent(tricky)!;
    expect(parts.trailing, 'rest');
    expect(jsonDecode(parts.json), isA<Map>());
  });

  test('unrecoverable content returns null', () {
    expect(BibleReference.tryParseContent('just words'), isNull);
    expect(BibleReference.tryParseContent(''), isNull);
    expect(BibleReference.splitContent('{"unterminated": '), isNull);
  });
}
