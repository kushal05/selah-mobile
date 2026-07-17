import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notify/features/notes/domain/models/block_type.dart';
import 'package:notify/features/notes/presentation/providers/note_editor_provider.dart';
import 'package:notify/features/notes/presentation/widgets/editor/editor_block_widget.dart';

/// The IME path is how a real Android paste actually arrives: the keyboard /
/// clipboard chip drops text straight into the field and `onChanged` fires —
/// bypassing both the context menu and the Ctrl+V handler.
///
/// `tester.enterText` reproduces that exactly (platform sets the value, then
/// onChanged), so these tests are the regression guard for markdown paste
/// silently staying literal on device.
void main() {
  late ProviderContainer container;
  late NoteEditorNotifier notifier;

  Future<void> pumpEditor(WidgetTester tester) async {
    container = ProviderContainer();
    container.listen(noteEditorProvider(null), (_, _) {}, fireImmediately: true);
    notifier = container.read(noteEditorProvider(null).notifier);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: EditorBlockWidget(
            block: notifier.state.document.blocks.first,
            noteId: null,
            blockIndex: 0,
            autoFocus: true,
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  /// Simulate the IME inserting [text] into the focused field.
  Future<void> imeInput(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField), text);
    await tester.pumpAndSettle();
  }

  List<EditorBlockSummary> blocks() => notifier.state.document.blocks
      .map((b) => EditorBlockSummary(b.type, b.content, b.formats.length))
      .toList();

  testWidgets('pasted markdown is parsed into formatted blocks', (tester) async {
    await pumpEditor(tester);
    await imeInput(tester, '# Title\n- one\n- two\n**bold** text');

    final result = blocks();
    expect(result[0].type, BlockType.heading1);
    expect(result[0].content, 'Title');
    expect(result[1].type, BlockType.bulletList);
    expect(result[1].content, 'one');
    expect(result[2].type, BlockType.bulletList);
    expect(result[3].type, BlockType.paragraph);
    expect(result[3].content, 'bold text');
    expect(result[3].formatCount, greaterThan(0),
        reason: 'inline bold must survive an IME paste');

    container.dispose();
  });

  testWidgets('pasted markdown table becomes a table block', (tester) async {
    await pumpEditor(tester);
    await imeInput(tester, 'Intro\n| a | b |\n|---|---|\n| 1 | 2 |');

    expect(notifier.state.document.blocks.any((b) => b.type == BlockType.table),
        true);
    container.dispose();
  });

  testWidgets('Enter still splits plainly', (tester) async {
    await pumpEditor(tester);
    await imeInput(tester, 'hello');
    await imeInput(tester, 'hello\n'); // Enter inserts exactly one '\n'

    final result = blocks();
    expect(result.length, 2);
    expect(result[0].content, 'hello');
    expect(result[0].type, BlockType.paragraph);
    container.dispose();
  });

  testWidgets('typing literal markdown then Enter must NOT convert it',
      (tester) async {
    await pumpEditor(tester);
    await imeInput(tester, '# not a heading');
    await imeInput(tester, '# not a heading\n');

    // Enter is a single '\n' insertion, so it must never be treated as a paste.
    expect(blocks().first.type, BlockType.paragraph);
    expect(blocks().first.content, '# not a heading');
    container.dispose();
  });

  testWidgets('paste after existing text keeps the head intact', (tester) async {
    await pumpEditor(tester);
    await imeInput(tester, 'Notes: ');
    await imeInput(tester, 'Notes: # Heading\nbody');

    final result = blocks();
    // The head is not markdown, so it stays as typed; the pasted lines follow.
    expect(result.first.content, startsWith('Notes: '));
    expect(result.any((b) => b.content == 'body'), true);
    container.dispose();
  });
}

class EditorBlockSummary {
  final BlockType type;
  final String content;
  final int formatCount;
  EditorBlockSummary(this.type, this.content, this.formatCount);
}
