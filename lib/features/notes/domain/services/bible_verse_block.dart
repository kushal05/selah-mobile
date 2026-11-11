import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../../../bible/domain/models/bible_reference.dart';
import '../models/block_type.dart';
import '../models/editor_block.dart';
import '../models/editor_document.dart';
import '../models/note_section.dart';

/// A Bible reference card for one verse, the same kind the editor's `@`
/// picker inserts: reference only, the text is looked up when it is shown.
EditorBlock buildBibleVerseBlock({
  required String book,
  required int chapter,
  required int verse,
  required String version,
}) {
  final ref = BibleReference(
    reference: BibleVerseReference(
      book: book,
      chapter: chapter,
      verses: [verse],
      version: version,
    ),
    text: const [],
    source: 'local',
    insertedAt: DateTime.now().millisecondsSinceEpoch,
    display: const BibleVerseDisplay(),
    pending: false,
  );
  return EditorBlock(
    id: const Uuid().v4(),
    type: BlockType.bibleReference,
    content: jsonEncode(ref.toJson()),
  );
}

/// [document] with [block] at the end of its main section, followed by an
/// empty line so there is somewhere to keep typing after a card.
///
/// A blank last line is used up rather than left above the card, so a note
/// that ends in an empty line does not gain a gap.
EditorDocument appendBlockAtEnd(EditorDocument document, EditorBlock block) {
  final blocks = List<EditorBlock>.from(document.blocks);
  final lastMain = blocks.lastIndexWhere((b) => b.section == NoteSection.main);
  final trailingLine = EditorBlock.paragraph();

  if (lastMain >= 0 &&
      blocks[lastMain].type == BlockType.paragraph &&
      blocks[lastMain].isEmpty) {
    blocks[lastMain] = block;
    blocks.insert(lastMain + 1, trailingLine);
  } else {
    final at = lastMain >= 0 ? lastMain + 1 : blocks.length;
    blocks.insert(at, block);
    blocks.insert(at + 1, trailingLine);
  }
  return EditorDocument(blocks: blocks);
}
