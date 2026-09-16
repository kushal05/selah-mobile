// Turning Bible reference blocks into "which tags are on which verse" — the
// path the whole feature exists for, and the one that had no positive test:
// the two existing index tests cover *when* it rebuilds, and both pass just as
// happily against an index that always comes back empty.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:notify/core/sync/models/note_block_model.dart';
import 'package:notify/features/bible/domain/models/bible_reference.dart';
import 'package:notify/features/bible/presentation/providers/verse_tag_providers.dart';

/// John is 43, Romans is 45; anything else is a book we cannot place.
int? resolve(String name) => const {'John': 43, 'Romans': 45}[name];

NoteBlockModel block(
  String id, {
  required String book,
  required int chapter,
  required List<int> verses,
  required List<String> tagIds,
}) =>
    NoteBlockModel(
      id: id,
      noteId: 'n1',
      blockType: BlockType.bibleReference,
      content: {
        'text': jsonEncode(BibleReference(
          reference: BibleVerseReference(
            book: book,
            chapter: chapter,
            verses: verses,
            version: 'nkjv',
          ),
          text: const [],
          tagIds: tagIds,
        ).toJson()),
      },
      orderIndex: 0,
      updatedAt: 0,
      version: 1,
      deleted: 0,
      createdAt: 0,
    );

NoteBlockModel rawBlock(String id, String text) => NoteBlockModel(
      id: id,
      noteId: 'n1',
      blockType: BlockType.bibleReference,
      content: {'text': text},
      orderIndex: 0,
      updatedAt: 0,
      version: 1,
      deleted: 0,
      createdAt: 0,
    );

void main() {
  test('a tagged verse is found under its key', () {
    final index = buildVerseTagIndex([
      block('b1', book: 'John', chapter: 3, verses: [16], tagIds: ['t1']),
    ], resolve);

    expect(index[(bookId: 43, chapter: 3, verse: 16)], {'t1'});
  });

  test('a range puts the tag on every verse in it', () {
    // The tag belongs to the whole reference, so all of 16, 17 and 18 carry it.
    final index = buildVerseTagIndex([
      block('b1',
          book: 'John', chapter: 3, verses: [16, 17, 18], tagIds: ['t1']),
    ], resolve);

    for (final v in [16, 17, 18]) {
      expect(index[(bookId: 43, chapter: 3, verse: v)], {'t1'},
          reason: 'verse $v missed the tag');
    }
  });

  test('two notes tagging the same verse give both tags', () {
    final index = buildVerseTagIndex([
      block('b1', book: 'John', chapter: 3, verses: [16], tagIds: ['t1']),
      block('b2', book: 'John', chapter: 3, verses: [16], tagIds: ['t2']),
    ], resolve);

    expect(index[(bookId: 43, chapter: 3, verse: 16)], {'t1', 't2'});
  });

  test('verses in other books and chapters stay separate', () {
    final index = buildVerseTagIndex([
      block('b1', book: 'John', chapter: 3, verses: [16], tagIds: ['t1']),
      block('b2', book: 'Romans', chapter: 3, verses: [16], tagIds: ['t2']),
      block('b3', book: 'John', chapter: 4, verses: [16], tagIds: ['t3']),
    ], resolve);

    expect(index[(bookId: 43, chapter: 3, verse: 16)], {'t1'});
    expect(index[(bookId: 45, chapter: 3, verse: 16)], {'t2'});
    expect(index[(bookId: 43, chapter: 4, verse: 16)], {'t3'});
  });

  test('an untagged reference contributes nothing', () {
    final index = buildVerseTagIndex([
      block('b1', book: 'John', chapter: 3, verses: [16], tagIds: const []),
    ], resolve);

    expect(index, isEmpty);
  });

  test('a book we cannot place is skipped, not guessed', () {
    final index = buildVerseTagIndex([
      block('b1', book: 'Hezekiah', chapter: 1, verses: [1], tagIds: ['t1']),
    ], resolve);

    expect(index, isEmpty);
  });

  test('a block whose JSON will not parse does not take the index down', () {
    final index = buildVerseTagIndex([
      rawBlock('bad', 'not json at all'),
      block('b1', book: 'John', chapter: 3, verses: [16], tagIds: ['t1']),
    ], resolve);

    expect(index[(bookId: 43, chapter: 3, verse: 16)], {'t1'},
        reason: 'one broken block should not lose the good ones');
  });

  test('a block with no text at all is skipped', () {
    final index = buildVerseTagIndex([rawBlock('empty', '')], resolve);

    expect(index, isEmpty);
  });
}
