// Backspace at the start of a line moves into the line above at the right
// place — not wherever the caret last sat in that line.
//
// The editor removed the line and recorded the line above as focused, but left
// the move itself to whatever took focus next. That field brought back its own
// last caret: if you had clicked into the middle of the line above earlier, the
// caret jumped there instead of to the join point (or the end, for an empty
// line). Driven through the real editor screen, so the caret checked is the one
// in the text field the person types into.

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:notify/core/database/sync_database.dart';
import 'package:notify/core/sync/providers/sync_providers.dart';
import 'package:notify/features/notes/presentation/providers/note_editor_provider.dart';
import 'package:notify/features/notes/presentation/screens/note_editor_screen.dart';
import 'package:notify/l10n/app_localizations.dart';

const _first = 'First line here';

void main() {
  late SyncDatabase db;
  late ProviderContainer container;

  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  setUp(() {
    db = SyncDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(overrides: [
      syncDatabaseProvider.overrideWithValue(db),
      currentUserIdProvider.overrideWith((ref) => 'test-user'),
      deviceIdProvider.overrideWith((ref) => 'test-device'),
    ]);
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  /// Bounded pumping: a focused field's caret blinks forever, so nothing
  /// ever settles.
  Future<void> frames(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  /// Two lines, `_first` and [second], with the caret left at offset 3 of the
  /// first — a stale caret from an earlier visit — and now at the start of the
  /// second. Returns the two block ids.
  Future<(String, String)> twoLines(WidgetTester tester, String second) async {
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: NoteEditorScreen(),
      ),
    ));
    await frames(tester);

    final editor = container.read(noteEditorProvider(null).notifier);
    final firstId = editor.state.document.blocks.first.id;
    editor.updateBlockContent(firstId, _first + second);
    editor.getBlockController(firstId).text = _first + second;
    editor.splitBlock(firstId, _first.length);
    await frames(tester);
    final secondId = editor.state.document.blocks[1].id;
    expect(editor.state.document.blocks[1].content, second,
        reason: 'precondition: two lines');

    // An earlier visit to the first line, leaving its caret at 3.
    editor.getBlockFocusNode(firstId).requestFocus();
    await frames(tester);
    editor.getBlockController(firstId).selection =
        const TextSelection.collapsed(offset: 3);
    await frames(tester);

    // Now at the start of the second line.
    editor.getBlockFocusNode(secondId).requestFocus();
    await frames(tester);
    editor.getBlockController(secondId).selection =
        const TextSelection.collapsed(offset: 0);
    await frames(tester);
    return (firstId, secondId);
  }

  /// Lets the debounced autosave fire and finish, so no timer outlives the
  /// test. After the assertions, so the save cannot be what they observed.
  Future<void> drainSave(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 2));
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pump(const Duration(seconds: 2));
  }

  void expectCaret(String blockId, int offset) {
    final editor = container.read(noteEditorProvider(null).notifier);
    expect(editor.getBlockFocusNode(blockId).hasFocus, isTrue,
        reason: 'the line above has the focus');
    expect(editor.getBlockController(blockId).selection,
        TextSelection.collapsed(offset: offset),
        reason: 'not the stale caret at 3');
  }

  testWidgets('joining a line onto the one above puts the caret at the join',
      (tester) async {
    final (firstId, secondId) = await twoLines(tester, 'Second');
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await frames(tester);

    final editor = container.read(noteEditorProvider(null).notifier);
    expect(editor.state.document.getBlockById(secondId), isNull);
    expect(editor.getBlockController(firstId).text, '${_first}Second');
    expectCaret(firstId, _first.length);
    await drainSave(tester);
  });

  testWidgets('deleting an empty line puts the caret at the end of the one '
      'above', (tester) async {
    final (firstId, secondId) = await twoLines(tester, '');
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await frames(tester);

    final editor = container.read(noteEditorProvider(null).notifier);
    expect(editor.state.document.getBlockById(secondId), isNull);
    expectCaret(firstId, _first.length);
    await drainSave(tester);
  });
}
