import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:notify/core/database/services/note_block_fts_service.dart';
import 'package:notify/features/bible/domain/models/bible_reference.dart';
import 'package:notify/features/notes/domain/models/note_table.dart';

/// What `extractPlainText` returns IS what gets stored in the FTS index, so it
/// determines what users can find. Bible reference blocks keep their JSON
/// payload in content['text']; indexing that verbatim made internal keys
/// searchable and buried the verse text.
void main() {
  String contentJson(Map<String, dynamic> m) => jsonEncode(m);

  /// Built from the real model so the fixture can't drift from production's
  /// payload shape (hand-written JSON silently used the wrong verse-text key).
  String bibleRefJson({
    String book = 'John',
    int chapter = 3,
    List<int> verses = const [16],
    String version = 'ESV',
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
        insertedAt: 1784196741600,
        display: const BibleVerseDisplay(),
        pending: false,
      ).toJson());

  group('extractPlainText — bible references', () {
    test('indexes the reference and verse text, not the JSON payload', () {
      final out = NoteBlockFtsService.extractPlainText(contentJson({
        'text': bibleRefJson(text: const [
          BibleVerseText(verse: 16, content: 'For God so loved the world'),
        ]),
      }));

      expect(out, contains('John'));
      expect(out, contains('For God so loved the world'));
      // Internal keys must not become searchable terms.
      expect(out, isNot(contains('insertedAt')));
      expect(out, isNot(contains('showVerseNumbers')));
      expect(out, isNot(contains('pending')));
      expect(out, isNot(contains('{')));
    });

    test('reference with no inline verse text still indexes the reference', () {
      final out = NoteBlockFtsService.extractPlainText(contentJson({
        'text': bibleRefJson(
            book: 'Psalms', chapter: 23, verses: const [1], version: 'KJV'),
      }));
      expect(out, contains('Psalms'));
      expect(out, isNot(contains('insertedAt')));
    });
  });

  group('extractPlainText — ordinary content is untouched', () {
    test('plain block text passes through', () {
      expect(
        NoteBlockFtsService.extractPlainText(
            contentJson({'text': 'just some note text'})),
        'just some note text',
      );
    });

    test('prose that merely mentions reference/braces is not mangled', () {
      const tricky = 'See the {reference} section, it is "reference" material';
      expect(
        NoteBlockFtsService.extractPlainText(contentJson({'text': tricky})),
        tricky,
      );
    });

    test('table blocks index their cell text', () {
      final table = NoteTable(
        rows: [
          [const NoteTableCell(text: 'Name'), const NoteTableCell(text: 'Qty')],
          [const NoteTableCell(text: 'Apples'), const NoteTableCell(text: '3')],
        ],
        alignments: const [],
      );
      final out = NoteBlockFtsService.extractPlainText(contentJson({
        'text': table.plainText,
        'table': table.toJson(),
      }));

      expect(out, contains('Apples'));
      expect(out, isNot(contains('"rows"')));
    });

    test('a JSON snippet pasted into a note is indexed verbatim', () {
      // Looks JSON-ish and even has a "reference" key, but it is not a
      // scripture reference — it must not be mangled into one.
      const pasted = '{"reference": {"id": 7}, "note": "api payload"}';
      expect(
        NoteBlockFtsService.extractPlainText(contentJson({'text': pasted})),
        pasted,
      );
    });

    test('empty and malformed content are safe', () {
      expect(NoteBlockFtsService.extractPlainText('not json'), '');
      expect(NoteBlockFtsService.extractPlainText(contentJson({})), '');
      expect(NoteBlockFtsService.extractPlainText(contentJson({'text': ''})), '');
    });
  });
}
