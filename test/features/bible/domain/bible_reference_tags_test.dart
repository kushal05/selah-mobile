// Verse tags ride the Bible reference block's JSON, so the round-trip has to
// be exact and the field has to be optional in both directions: blocks written
// before it existed must still load, and blocks with no tags must still write
// byte-identical JSON or the editor's unchanged-check stops suppressing a
// redundant write on every 300ms save.

import 'package:flutter_test/flutter_test.dart';
import 'package:notify/features/bible/domain/models/bible_reference.dart';

BibleReference makeRef({List<String> tagIds = const []}) => BibleReference(
      reference: const BibleVerseReference(
        book: 'John',
        chapter: 3,
        verses: [16, 17],
        version: 'nkjv',
      ),
      text: const [],
      insertedAt: 1700000000000,
      tagIds: tagIds,
    );

void main() {
  test('tags survive a round-trip', () {
    final json = makeRef(tagIds: ['t1', 't2']).toJson();
    expect(BibleReference.fromJson(json).tagIds, ['t1', 't2']);
  });

  test('a block written before verse tags existed still loads', () {
    final json = makeRef().toJson()..remove('tagIds');
    expect(BibleReference.fromJson(json).tagIds, isEmpty);
  });

  test('no tags means no key, so unchanged blocks are not rewritten', () {
    expect(makeRef().toJson().containsKey('tagIds'), isFalse);
  });

  test('the old flat format still loads, with no tags', () {
    final ref = BibleReference.fromJson({
      'book': 'John',
      'chapter': 3,
      'verseStart': 16,
      'verseEnd': 17,
      'version': 'kjv',
      'text': 'For God so loved...',
    });
    expect(ref.reference.verses, [16, 17]);
    expect(ref.tagIds, isEmpty);
  });

  test('junk in the tag list is dropped rather than crashing the block', () {
    final json = makeRef().toJson();
    json['tagIds'] = ['good', 42, null, 'also-good'];
    expect(BibleReference.fromJson(json).tagIds, ['good', 'also-good']);
  });

  test('copyWith replaces tags and leaves the rest alone', () {
    final ref = makeRef(tagIds: ['t1']);
    final updated = ref.copyWith(tagIds: ['t2', 't3']);

    expect(updated.tagIds, ['t2', 't3']);
    expect(updated.reference, ref.reference);
    expect(updated.insertedAt, ref.insertedAt);
  });

  test('two references differing only by tags are not equal', () {
    // Equality drives the editor's "has this block changed" check; if tags
    // were left out of props, adding one would never be saved.
    expect(makeRef(tagIds: ['t1']), isNot(makeRef()));
  });
}
