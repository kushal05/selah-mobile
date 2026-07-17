import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:notify/core/sync/models/note_block_model.dart';
import 'package:notify/features/bible/domain/models/bible_reference.dart';
import 'package:notify/features/notes/domain/models/note_table.dart';

/// `displayText` is the one rule every user-facing surface uses to turn a block
/// into text (version history, revision diffs, previews). Bible reference
/// blocks store JSON in content['text'], so `plainText` is NOT safe to show.
void main() {
  NoteBlockModel blockOf(BlockType type, Map<String, dynamic> content) =>
      NoteBlockModel.create(
        id: 'b1',
        noteId: 'n1',
        blockType: type,
        content: content,
        orderIndex: 0,
      );

  final refJson = jsonEncode(BibleReference(
    reference: const BibleVerseReference(
      book: 'John',
      chapter: 3,
      verses: [16],
      version: 'kjv',
    ),
    text: const [BibleVerseText(verse: 16, content: 'For God so loved')],
    source: 'local',
    insertedAt: 1,
    display: const BibleVerseDisplay(),
    pending: false,
  ).toJson());

  test('bible reference: displayText is readable where plainText is JSON', () {
    final block = blockOf(BlockType.bibleReference, {'text': refJson});

    // The raw accessor still exposes the payload...
    expect(block.plainText, contains('"reference"'));
    // ...but what users see must not.
    expect(block.displayText, contains('John 3:16'));
    expect(block.displayText, contains('For God so loved'));
    expect(block.displayText, isNot(contains('{')));
    expect(block.displayText, isNot(contains('insertedAt')));
  });

  test('ordinary text blocks pass through unchanged', () {
    final block = blockOf(BlockType.paragraph, {'text': 'hello world'});
    expect(block.displayText, 'hello world');
  });

  test('a note that merely mentions JSON is not mangled', () {
    const tricky = '{"reference": {"id": 7}} was the payload';
    final block = blockOf(BlockType.paragraph, {'text': tricky});
    expect(block.displayText, tricky);
  });

  test('table blocks already store readable text', () {
    final table = NoteTable(
      rows: [
        [const NoteTableCell(text: 'Name'), const NoteTableCell(text: 'Qty')],
      ],
      alignments: const [],
    );
    final block = blockOf(BlockType.table, {
      'text': table.plainText,
      'table': table.toJson(),
    });
    expect(block.displayText, contains('Name'));
    expect(block.displayText, isNot(contains('"rows"')));
  });

  test('empty content is safe', () {
    expect(blockOf(BlockType.paragraph, {}).displayText, '');
    expect(blockOf(BlockType.paragraph, {'text': ''}).displayText, '');
  });
}
