import 'package:flutter/widgets.dart' show TextSelection;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:notify/features/notes/domain/models/block_type.dart';
import 'package:notify/features/notes/domain/models/editor_cursor.dart';
import 'package:notify/features/notes/presentation/providers/note_editor_provider.dart';

/// Exercises block range-selection and the undoable multi-block delete on a new
/// note (no DB needed — `_initialize` is a no-op for a null noteId).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;
  late NoteEditorNotifier notifier;

  setUp(() {
    container = ProviderContainer();
    notifier = container.read(noteEditorProvider(null).notifier);
  });

  tearDown(() => container.dispose());

  /// Build a 4-block document: a, b, c, d.
  List<String> seedFourBlocks() {
    final id = notifier.state.document.blocks.first.id;
    notifier.pasteText(
      blockId: id,
      selectionStart: 0,
      selectionEnd: 0,
      rawText: 'a\nb\nc\nd',
    );
    return notifier.state.document.blocks.map((b) => b.id).toList();
  }

  Set<String> selected() => notifier.state.uiState.selectedBlockIds;

  group('selectBlockRange', () {
    test('selects the inclusive range in document order', () {
      final ids = seedFourBlocks();
      notifier.toggleBlockSelection(ids[1]); // anchor = b
      notifier.selectBlockRange(ids[3]); // extend to d

      expect(selected(), {ids[1], ids[2], ids[3]});
    });

    test('extends symmetrically when dragging back above the anchor', () {
      final ids = seedFourBlocks();
      notifier.toggleBlockSelection(ids[2]); // anchor = c
      notifier.selectBlockRange(ids[0]); // extend up to a

      expect(selected(), {ids[0], ids[1], ids[2]});
    });

    test('re-extending shrinks the range back toward the anchor', () {
      final ids = seedFourBlocks();
      notifier.toggleBlockSelection(ids[0]); // anchor = a
      notifier.selectBlockRange(ids[3]); // a..d
      expect(selected(), {ids[0], ids[1], ids[2], ids[3]});

      notifier.selectBlockRange(ids[1]); // shrink to a..b
      expect(selected(), {ids[0], ids[1]});
    });
  });

  group('deleteSelectedBlocks', () {
    test('deletes a contiguous range and is undoable in one step', () {
      final ids = seedFourBlocks();
      notifier.toggleBlockSelection(ids[1]);
      notifier.selectBlockRange(ids[2]); // select b, c

      notifier.deleteSelectedBlocks();
      expect(notifier.state.document.blocks.map((b) => b.id), [ids[0], ids[3]]);
      expect(selected(), isEmpty);

      notifier.undo();
      expect(notifier.state.document.blocks.map((b) => b.id), ids);
      expect(
        notifier.state.document.blocks.map((b) => b.content),
        ['a', 'b', 'c', 'd'],
      );
    });

    test('a non-contiguous selection deletes only selected blocks, one undo',
        () {
      final ids = seedFourBlocks();
      notifier.toggleBlockSelection(ids[0]);
      notifier.toggleBlockSelection(ids[2]); // select a and c, skip b

      notifier.deleteSelectedBlocks();
      expect(notifier.state.document.blocks.map((b) => b.id), [ids[1], ids[3]]);

      notifier.undo();
      expect(notifier.state.document.blocks.map((b) => b.content),
          ['a', 'b', 'c', 'd']);
    });

    test('refuses to delete every block', () {
      final ids = seedFourBlocks();
      for (final id in ids) {
        notifier.toggleBlockSelection(id);
      }
      notifier.deleteSelectedBlocks();
      expect(notifier.state.document.blocks.length, 4);
    });
  });

  group('deleteSelection (cross-block text selection)', () {
    /// Seed blocks with the given contents by pasting them as newline-joined
    /// text into the empty first block.
    List<String> seedContents(List<String> contents) {
      final id = notifier.state.document.blocks.first.id;
      notifier.pasteText(
        blockId: id,
        selectionStart: 0,
        selectionEnd: 0,
        rawText: contents.join('\n'),
      );
      return notifier.state.document.blocks.map((b) => b.id).toList();
    }

    test('merges head of first and tail of last into one block', () {
      final ids = seedContents(['hello', 'middle', 'world']);
      // Select from "he|llo" through "wor|ld".
      notifier.deleteSelection(EditorSelection(
        anchor: EditorCursor(blockId: ids[0], offset: 2),
        focus: EditorCursor(blockId: ids[2], offset: 3),
      ));

      final blocks = notifier.state.document.blocks;
      expect(blocks.length, 1);
      expect(blocks.first.content, 'held'); // "he" + "ld"
    });

    test('is undoable in one step', () {
      final ids = seedContents(['hello', 'middle', 'world']);
      notifier.deleteSelection(EditorSelection(
        anchor: EditorCursor(blockId: ids[0], offset: 2),
        focus: EditorCursor(blockId: ids[2], offset: 3),
      ));
      expect(notifier.state.document.blocks.length, 1);

      notifier.undo();
      expect(notifier.state.document.blocks.map((b) => b.content),
          ['hello', 'middle', 'world']);
    });

    test('works regardless of anchor/focus direction', () {
      final ids = seedContents(['hello', 'world']);
      // Focus before anchor in document order.
      notifier.deleteSelection(EditorSelection(
        anchor: EditorCursor(blockId: ids[1], offset: 3),
        focus: EditorCursor(blockId: ids[0], offset: 2),
      ));
      expect(notifier.state.document.blocks.single.content, 'held');
    });

    test('preserves and rebases formatting on both surviving fragments', () {
      final ids = seedContents(['ABCD', 'WXYZ']);
      // Bold "AB" (0..2) in the first block, bold "YZ" (2..4) in the second.
      notifier.toggleFormat(blockId: ids[0], start: 0, end: 2, bold: true);
      notifier.toggleFormat(blockId: ids[1], start: 2, end: 4, bold: true);

      // Keep "ABC" of the first and "YZ" of the second → "ABCYZ".
      notifier.deleteSelection(EditorSelection(
        anchor: EditorCursor(blockId: ids[0], offset: 3),
        focus: EditorCursor(blockId: ids[1], offset: 2),
      ));

      final merged = notifier.state.document.blocks.single;
      expect(merged.content, 'ABCYZ');
      // "AB" still bold at 0..2.
      expect(
          merged.formats.any((f) => f.isBold && f.start == 0 && f.end == 2),
          true);
      // "YZ" now at 3..5, still bold.
      expect(
          merged.formats.any((f) => f.isBold && f.start == 3 && f.end == 5),
          true);
    });

    test('collapsed or single-block selection is a no-op', () {
      final ids = seedContents(['hello', 'world']);
      notifier.deleteSelection(EditorSelection.collapsed(
        EditorCursor(blockId: ids[0], offset: 2),
      ));
      notifier.deleteSelection(EditorSelection(
        anchor: EditorCursor(blockId: ids[0], offset: 1),
        focus: EditorCursor(blockId: ids[0], offset: 3),
      ));
      expect(notifier.state.document.blocks.length, 2);
    });

    test('an atomic end block is dropped whole — no JSON leaks into text', () {
      // text, table, text
      final id = notifier.state.document.blocks.first.id;
      notifier.pasteText(
        blockId: id,
        selectionStart: 0,
        selectionEnd: 0,
        rawText: 'hello\n| a | b |\n|---|---|\n| 1 | 2 |\nworld',
      );
      final blocks = notifier.state.document.blocks;
      // Find the table block and select from the first text block through it.
      final tableIdx = blocks.indexWhere((b) => b.type.isAtomic);
      expect(tableIdx, greaterThan(0));

      notifier.deleteSelection(EditorSelection(
        anchor: EditorCursor(blockId: blocks.first.id, offset: 2),
        focus: EditorCursor(blockId: blocks[tableIdx].id, offset: 0),
      ));

      // No non-atomic block may contain the table JSON.
      for (final b in notifier.state.document.blocks) {
        if (b.type.isAtomic) continue;
        expect(b.content, isNot(contains('{"rows"')),
            reason: 'table JSON leaked into ${b.type.name}');
      }
    });
  });

  group('textSelectionForBlock (highlight ranges)', () {
    List<String> seedContents(List<String> contents) {
      final id = notifier.state.document.blocks.first.id;
      notifier.pasteText(
        blockId: id,
        selectionStart: 0,
        selectionEnd: 0,
        rawText: contents.join('\n'),
      );
      return notifier.state.document.blocks.map((b) => b.id).toList();
    }

    test('partial at the ends, full in the middle, null outside', () {
      final ids = seedContents(['hello', 'middle', 'world', 'extra']);
      notifier.setTextRangeSelection(
        EditorCursor(blockId: ids[0], offset: 2), // "he|llo"
        EditorCursor(blockId: ids[2], offset: 3), // "wor|ld"
      );

      // First block: from offset 2 to end (5).
      expect(notifier.textSelectionForBlock(ids[0]),
          const TextSelection(baseOffset: 2, extentOffset: 5));
      // Middle block: whole content (0..6).
      expect(notifier.textSelectionForBlock(ids[1]),
          const TextSelection(baseOffset: 0, extentOffset: 6));
      // Last block: start to offset 3.
      expect(notifier.textSelectionForBlock(ids[2]),
          const TextSelection(baseOffset: 0, extentOffset: 3));
      // Outside the range.
      expect(notifier.textSelectionForBlock(ids[3]), isNull);
    });

    test('normalizes regardless of anchor/focus direction', () {
      final ids = seedContents(['hello', 'world']);
      notifier.setTextRangeSelection(
        EditorCursor(blockId: ids[1], offset: 3),
        EditorCursor(blockId: ids[0], offset: 2),
      );
      expect(notifier.textSelectionForBlock(ids[0]),
          const TextSelection(baseOffset: 2, extentOffset: 5));
      expect(notifier.textSelectionForBlock(ids[1]),
          const TextSelection(baseOffset: 0, extentOffset: 3));
    });

    test('a collapsed / single-block selection highlights nothing', () {
      final ids = seedContents(['hello', 'world']);
      notifier.setTextRangeSelection(
        EditorCursor(blockId: ids[0], offset: 1),
        EditorCursor(blockId: ids[0], offset: 3),
      );
      expect(notifier.textSelectionForBlock(ids[0]), isNull);
    });
  });
}
