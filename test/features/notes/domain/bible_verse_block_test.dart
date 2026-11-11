// "Add to notes" from the Bible reader puts the verse in the note's body as a
// reference card, at the end, with a line left to keep typing on.

import 'package:flutter_test/flutter_test.dart';

import 'package:notify/features/bible/domain/models/bible_reference.dart';
import 'package:notify/features/notes/domain/models/block_type.dart';
import 'package:notify/features/notes/domain/models/editor_block.dart';
import 'package:notify/features/notes/domain/models/editor_document.dart';
import 'package:notify/features/notes/domain/models/note_section.dart';
import 'package:notify/features/notes/domain/services/bible_verse_block.dart';

EditorBlock _para(String text, {NoteSection section = NoteSection.main}) =>
    EditorBlock.paragraph(section: section).copyWith(content: text);

EditorBlock _card() => buildBibleVerseBlock(
    book: 'John', chapter: 3, verse: 16, version: 'NASB');

void main() {
  group('buildBibleVerseBlock', () {
    test('is a reference card for that verse in that version', () {
      final block = _card();
      expect(block.type, BlockType.bibleReference);

      final ref = BibleReference.tryParseContent(block.content)!;
      expect(ref.reference.book, 'John');
      expect(ref.reference.chapter, 3);
      expect(ref.reference.verses, [16]);
      expect(ref.reference.version, 'NASB');
      expect(ref.text, isEmpty, reason: 'text is looked up when it is shown');
    });
  });

  group('appendBlockAtEnd', () {
    test('goes after the last line and leaves a blank one under it', () {
      final doc = EditorDocument(blocks: [_para('one'), _para('two')]);
      final card = _card();

      final out = appendBlockAtEnd(doc, card).blocks;

      expect(out.map((b) => b.type), [
        BlockType.paragraph,
        BlockType.paragraph,
        BlockType.bibleReference,
        BlockType.paragraph,
      ]);
      expect(out[0].content, 'one');
      expect(out[1].content, 'two');
      expect(out[2].id, card.id);
      expect(out[3].content, isEmpty);
    });

    test('uses up a blank last line instead of leaving a gap above', () {
      final doc = EditorDocument(blocks: [_para('one'), _para('')]);

      final out = appendBlockAtEnd(doc, _card()).blocks;

      expect(out.map((b) => b.type), [
        BlockType.paragraph,
        BlockType.bibleReference,
        BlockType.paragraph,
      ]);
      expect(out[0].content, 'one');
    });

    test('goes after the main section, not after the prayer', () {
      final doc = EditorDocument(blocks: [
        _para('main'),
        _para('prayer', section: NoteSection.prayer),
      ]);

      final out = appendBlockAtEnd(doc, _card()).blocks;

      expect(out.map((b) => b.section), [
        NoteSection.main,
        NoteSection.main,
        NoteSection.main,
        NoteSection.prayer,
      ]);
      expect(out[1].type, BlockType.bibleReference);
      expect(out.last.content, 'prayer');
    });

    test('works on a note that is one empty line', () {
      final out = appendBlockAtEnd(EditorDocument.empty(), _card()).blocks;
      expect(out.map((b) => b.type),
          [BlockType.bibleReference, BlockType.paragraph]);
    });

    test('does not change the document it was given', () {
      final doc = EditorDocument(blocks: [_para('one')]);
      appendBlockAtEnd(doc, _card());
      expect(doc.blocks, hasLength(1));
    });
  });
}
