import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notify/features/notes/presentation/providers/note_editor_provider.dart';
import 'package:notify/features/notes/presentation/widgets/editor/editor_block_widget.dart';

/// Verifies the Ctrl/Cmd+V interception actually suppresses Flutter's built-in
/// paste — if it didn't, the native paste would ALSO insert the clipboard text
/// and we'd see the content duplicated.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.getData') {
        return <String, dynamic>{'text': 'pasted'};
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  testWidgets('Ctrl+V pastes exactly once', (tester) async {
    final container = ProviderContainer();
    // Hold a subscription so the autoDispose provider stays alive for the test.
    container.listen(noteEditorProvider(null), (_, _) {}, fireImmediately: true);
    final notifier = container.read(noteEditorProvider(null).notifier);
    final block = notifier.state.document.blocks.first;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: EditorBlockWidget(
              block: block,
              noteId: null,
              blockIndex: 0,
              autoFocus: true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    final blocks = notifier.state.document.blocks;
    final blockCount = blocks.length;
    final content = blocks.first.content;

    // Dispose inside the body so the autosave debounce timer is cancelled
    // before the framework's pending-timer invariant check.
    container.dispose();

    // Exactly one paste: 'pasted', not 'pastedpasted'.
    expect(blockCount, 1);
    expect(content, 'pasted');
  });
}
