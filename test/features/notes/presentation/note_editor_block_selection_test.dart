import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
}
