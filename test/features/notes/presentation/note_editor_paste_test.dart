import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:notify/features/notes/domain/models/block_type.dart';
import 'package:notify/features/notes/domain/models/note_table.dart';
import 'package:notify/features/notes/presentation/providers/note_editor_provider.dart';

/// Exercises the real [NoteEditorNotifier.pasteText] splice + undo/redo on a
/// new note (no DB needed — `_initialize` is a no-op for a null noteId).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;
  late NoteEditorNotifier notifier;

  setUp(() {
    container = ProviderContainer();
    notifier = container.read(noteEditorProvider(null).notifier);
  });

  tearDown(() => container.dispose());

  String firstBlockId() => notifier.state.document.blocks.first.id;

  test('paste multi-line markdown into empty block splices typed blocks', () {
    final id = firstBlockId();
    notifier.pasteText(
      blockId: id,
      selectionStart: 0,
      selectionEnd: 0,
      rawText: '# Title\n- one\n- two\nplain **bold** text',
    );

    final blocks = notifier.state.document.blocks;
    expect(blocks.length, 4);
    expect(blocks[0].type, BlockType.heading1);
    expect(blocks[0].content, 'Title');
    expect(blocks[1].type, BlockType.bulletList);
    expect(blocks[2].type, BlockType.bulletList);
    expect(blocks[3].type, BlockType.paragraph);
    expect(blocks[3].content, 'plain bold text');
    expect(blocks[3].formats.any((f) => f.isBold), true);

    // A controller exists for every block.
    for (final b in blocks) {
      expect(notifier.getBlockController(b.id).text, b.content);
    }
  });

  test('paste preserves head/tail formatting around the caret', () {
    final id = firstBlockId();
    // Seed the block with "ABCD" where "BC" is bold, caret between B and C.
    notifier.updateBlockContent(id, 'ABCD');
    notifier.toggleFormat(blockId: id, start: 1, end: 3, bold: true);

    notifier.pasteText(
      blockId: id,
      selectionStart: 2, // between B and C
      selectionEnd: 2,
      rawText: 'X\nY',
    );

    final blocks = notifier.state.document.blocks;
    expect(blocks.length, 2);
    // Head: "ABX" with bold still covering "B".
    expect(blocks[0].content, 'ABX');
    expect(blocks[0].formats.any((f) => f.isBold && f.start == 1 && f.end == 2),
        true);
    // Tail: "YCD" with bold still covering "C" (offset 1).
    expect(blocks[1].content, 'YCD');
    expect(blocks[1].formats.any((f) => f.isBold && f.start == 1 && f.end == 2),
        true);
  });

  group('atomic blocks (table) are never concatenated with text', () {
    const tbl = '| a | b |\n|---|---|\n| 1 | 2 |';

    /// No block that renders its content as TEXT may contain table JSON.
    void expectNoJsonLeak() {
      for (final b in notifier.state.document.blocks) {
        if (b.type.isAtomic) continue;
        expect(b.content, isNot(contains('{"rows"')),
            reason: '${b.type.name} block leaked table JSON as text');
      }
    }

    test('pasted after existing text: head stays its own block', () {
      final id = firstBlockId();
      notifier.updateBlockContent(id, 'Here is my table: ');
      notifier.pasteText(
          blockId: id, selectionStart: 18, selectionEnd: 18, rawText: tbl);

      expectNoJsonLeak();
      final blocks = notifier.state.document.blocks;
      expect(blocks[0].content, 'Here is my table: ');
      expect(blocks[1].type, BlockType.table);
    });

    test('pasted mid-text: splits head / table / tail', () {
      final id = firstBlockId();
      notifier.updateBlockContent(id, 'AAABBB');
      notifier.pasteText(
          blockId: id, selectionStart: 3, selectionEnd: 3, rawText: tbl);

      expectNoJsonLeak();
      final blocks = notifier.state.document.blocks;
      expect(blocks.map((b) => b.type).toList(),
          [BlockType.paragraph, BlockType.table, BlockType.paragraph]);
      expect(blocks.first.content, 'AAA');
      expect(blocks.last.content, 'BBB');
    });

    test('pasted before existing text: tail keeps its own block', () {
      final id = firstBlockId();
      notifier.updateBlockContent(id, 'trailing words');
      notifier.pasteText(
          blockId: id, selectionStart: 0, selectionEnd: 0, rawText: tbl);

      expectNoJsonLeak();
      expect(notifier.state.document.blocks.last.content, 'trailing words');
    });

    test('a note never ends on a caret-less card', () {
      final id = firstBlockId();
      notifier.pasteText(
          blockId: id, selectionStart: 0, selectionEnd: 0, rawText: tbl);

      final blocks = notifier.state.document.blocks;
      expect(blocks.first.type, BlockType.table);
      // Trailing paragraph exists so the user can keep typing.
      expect(blocks.last.type, BlockType.paragraph);
      expect(notifier.state.cursor.blockId, blocks.last.id);
    });

    test('table JSON stays parseable after every paste shape', () {
      final id = firstBlockId();
      notifier.updateBlockContent(id, 'AAABBB');
      notifier.pasteText(
          blockId: id, selectionStart: 3, selectionEnd: 3, rawText: tbl);

      final table = notifier.state.document.blocks
          .firstWhere((b) => b.type == BlockType.table);
      final decoded =
          NoteTable.fromJson(jsonDecode(table.content) as Map<String, dynamic>);
      expect(decoded.header.map((c) => c.text).toList(), ['a', 'b']);
      expect(decoded.body.single.map((c) => c.text).toList(), ['1', '2']);
    });
  });

  test('undo restores the original single block; redo re-applies', () {
    final id = firstBlockId();
    notifier.updateBlockContent(id, 'hello');

    notifier.pasteText(
      blockId: id,
      selectionStart: 5,
      selectionEnd: 5,
      rawText: '\n# world',
    );
    expect(notifier.state.document.blocks.length, 2);

    notifier.undo();
    final afterUndo = notifier.state.document.blocks;
    expect(afterUndo.length, 1);
    expect(afterUndo.first.content, 'hello');

    notifier.redo();
    expect(notifier.state.document.blocks.length, 2);
    expect(notifier.state.document.blocks[1].type, BlockType.heading1);
    expect(notifier.state.document.blocks[1].content, 'world');
  });
}
