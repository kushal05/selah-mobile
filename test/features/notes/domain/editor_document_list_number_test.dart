import 'package:flutter_test/flutter_test.dart';
import 'package:notify/features/notes/domain/models/block_type.dart';
import 'package:notify/features/notes/domain/models/editor_block.dart';
import 'package:notify/features/notes/domain/models/editor_document.dart';
import 'package:notify/features/notes/domain/models/note_section.dart';

EditorBlock _numbered(String id, NoteSection section, {int indent = 0}) =>
    EditorBlock(
      id: id,
      type: BlockType.numberedList,
      content: id,
      indentLevel: indent,
      section: section,
    );

EditorBlock _para(String id, NoteSection section) => EditorBlock(
      id: id,
      type: BlockType.paragraph,
      content: id,
      section: section,
    );

void main() {
  group('EditorDocument.calculateListNumber', () {
    test('numbers consecutive items in a single section', () {
      final doc = EditorDocument(blocks: [
        _numbered('a', NoteSection.main),
        _numbered('b', NoteSection.main),
        _numbered('c', NoteSection.main),
      ]);

      expect(doc.calculateListNumber('a'), 1);
      expect(doc.calculateListNumber('b'), 2);
      expect(doc.calculateListNumber('c'), 3);
    });

    test('a non-numbered block resets the count', () {
      final doc = EditorDocument(blocks: [
        _numbered('a', NoteSection.main),
        _para('p', NoteSection.main),
        _numbered('b', NoteSection.main),
      ]);

      expect(doc.calculateListNumber('a'), 1);
      expect(doc.calculateListNumber('b'), 1);
    });

    test(
        'numbering is unaffected by interleaved blocks from another section '
        '(regression: items previously all showed 1)', () {
      // Simulates the on-load state: blocks are persisted with per-section
      // order indices and re-loaded ordered by orderIndex alone, so a
      // personal-application block interleaves between the main-section
      // numbered items.
      final doc = EditorDocument(blocks: [
        _numbered('m1', NoteSection.main),
        _para('pa0', NoteSection.personalApplication),
        _numbered('m2', NoteSection.main),
        _para('pa1', NoteSection.personalApplication),
        _numbered('m3', NoteSection.main),
      ]);

      expect(doc.calculateListNumber('m1'), 1);
      expect(doc.calculateListNumber('m2'), 2);
      expect(doc.calculateListNumber('m3'), 3);
    });

    test('numbered items within the personal-application section increment', () {
      final doc = EditorDocument(blocks: [
        _numbered('m1', NoteSection.main),
        _numbered('pa1', NoteSection.personalApplication),
        _numbered('pa2', NoteSection.personalApplication),
        _numbered('pa3', NoteSection.personalApplication),
      ]);

      expect(doc.calculateListNumber('pa1'), 1);
      expect(doc.calculateListNumber('pa2'), 2);
      expect(doc.calculateListNumber('pa3'), 3);
    });

    test('nested (indented) children do not break the parent count', () {
      final doc = EditorDocument(blocks: [
        _numbered('a', NoteSection.main),
        _numbered('a-child', NoteSection.main, indent: 1),
        _numbered('b', NoteSection.main),
      ]);

      expect(doc.calculateListNumber('a'), 1);
      expect(doc.calculateListNumber('a-child'), 1);
      expect(doc.calculateListNumber('b'), 2);
    });
  });
}
