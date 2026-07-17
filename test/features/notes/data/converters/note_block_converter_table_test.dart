import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:notify/core/sync/models/note_block_model.dart' as sync;
import 'package:notify/features/notes/data/converters/note_block_converter.dart';
import 'package:notify/features/notes/domain/models/block_type.dart';
import 'package:notify/features/notes/domain/models/editor_block.dart';
import 'package:notify/features/notes/domain/models/note_table.dart';

/// `table` is a newer BlockType whose structure is JSON. Several consumers read
/// `content['text']` blindly and would surface that JSON to users:
///   * app versions predating `table` (they map it to `paragraph`),
///   * PDF export (`PdfExportService._blockToWidget`'s default case),
///   * FTS search indexing (`NoteBlockFtsService.extractPlainText`).
/// So the persisted payload MUST keep readable text in 'text' and the structure
/// in an additive 'table' key. These tests pin that contract.
void main() {
  final table = NoteTable(
    rows: [
      [const NoteTableCell(text: 'Name'), const NoteTableCell(text: 'Qty')],
      [const NoteTableCell(text: 'Apples'), const NoteTableCell(text: '3')],
    ],
    alignments: const [TableColumnAlign.left, TableColumnAlign.right],
  );

  EditorBlock tableBlock() => EditorBlock(
        id: 't1',
        type: BlockType.table,
        content: jsonEncode(table.toJson()),
      );

  group('table persistence', () {
    test('content["text"] is readable text, never raw JSON', () {
      final map = NoteBlockConverter.buildContentMap(tableBlock());

      final text = map['text'] as String;
      expect(text, contains('Apples'));
      expect(text, isNot(contains('{')));
      expect(text, isNot(contains('"rows"')));
      // Structure preserved separately for clients that understand tables.
      expect(map['table'], isA<Map<String, dynamic>>());
    });

    test('round-trips back to an identical table block', () {
      final map = NoteBlockConverter.buildContentMap(tableBlock());
      final model = sync.NoteBlockModel.create(
        id: 't1',
        noteId: 'n1',
        blockType: sync.BlockType.table,
        content: map,
        orderIndex: 0,
      );

      final restored = NoteBlockConverter.toEditorBlock(model);
      expect(restored.type, BlockType.table);

      final restoredTable =
          NoteTable.fromJson(jsonDecode(restored.content) as Map<String, dynamic>);
      expect(restoredTable, table);
    });

    test('degrades to a paragraph when the structure is missing', () {
      // Simulates a client that rewrote the block without the 'table' key.
      final model = sync.NoteBlockModel.create(
        id: 't1',
        noteId: 'n1',
        blockType: sync.BlockType.table,
        content: {'text': 'Name Qty Apples 3'},
        orderIndex: 0,
      );

      final restored = NoteBlockConverter.toEditorBlock(model);
      expect(restored.type, BlockType.paragraph);
      expect(restored.content, 'Name Qty Apples 3');
    });

    test('malformed table content does not throw', () {
      const bad = EditorBlock(
          id: 'x', type: BlockType.table, content: 'not json');
      expect(NoteBlockConverter.buildContentMap(bad), {'text': ''});
    });
  });
}
