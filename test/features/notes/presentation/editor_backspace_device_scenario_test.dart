// Reproduces the on-device sequence: the line above the card has its caret in
// the MIDDLE (left there by an earlier merge), so "went to the end of the line
// above" cannot be confused with "restored the old caret".
//
//   HelloWorld (caret at 5) | John 3:16 card | empty line | Tail

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:notify/core/database/sync_database.dart';
import 'package:notify/core/sync/providers/sync_providers.dart';
import 'package:notify/features/bible/domain/models/bible_reference.dart';
import 'package:notify/features/bible/presentation/providers/bible_providers.dart';
import 'package:notify/features/notes/domain/models/block_type.dart';
import 'package:notify/features/notes/presentation/providers/note_editor_provider.dart';
import 'package:notify/features/notes/presentation/screens/note_editor_screen.dart';
import 'package:notify/l10n/app_localizations.dart';

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
      bibleTranslationsProvider.overrideWithValue(const ['KJV']),
      verseLookupProvider.overrideWith((ref, verseRef) => [
            const BibleVerseText(verse: 16, content: 'For God so loved')
          ]),
    ]);
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  Future<void> frames(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> drainSave(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 2));
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pump(const Duration(seconds: 2));
  }

  testWidgets('device sequence: empty line, then Tail, under a card',
      (tester) async {
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

    final helloId = editor.state.document.blocks.first.id;
    editor.updateBlockContent(helloId, 'HelloWorld');
    editor.getBlockController(helloId).text = 'HelloWorld';
    editor.ensureBibleReferenceTriggeredBlock();
    editor.insertBibleReferenceBlock(
        book: 'John', chapter: 3, verses: const [16], version: 'KJV');
    await frames(tester);

    // [HelloWorld][card][empty] -> add Tail after the empty line.
    var blocks = editor.state.document.blocks;
    expect(blocks.map((b) => b.type),
        [BlockType.paragraph, BlockType.bibleReference, BlockType.paragraph]);
    final cardId = blocks[1].id;
    final cardContent = blocks[1].content;
    final emptyId = blocks[2].id;
    editor.splitBlock(emptyId, 0);
    await frames(tester);
    blocks = editor.state.document.blocks;
    expect(blocks.length, 4);
    final tailId = blocks[3].id;
    editor.updateBlockContent(tailId, 'Tail');
    editor.getBlockController(tailId).text = 'Tail';
    await frames(tester);

    // Leave the caret in the MIDDLE of HelloWorld, as the earlier merge did.
    editor.getBlockFocusNode(helloId).requestFocus();
    await frames(tester);
    editor.getBlockController(helloId).selection =
        const TextSelection.collapsed(offset: 5);
    await frames(tester);

    // Test 2: backspace in the empty line under the card.
    editor.getBlockFocusNode(emptyId).requestFocus();
    await frames(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await frames(tester);

    expect(editor.state.document.getBlockById(emptyId), isNull,
        reason: 'empty line removed');
    expect(editor.getBlockFocusNode(helloId).hasFocus, isTrue,
        reason: 'focus moved to the line above the card');
    expect(editor.getBlockController(helloId).selection,
        const TextSelection.collapsed(offset: 10),
        reason: 'caret at the END of the line above, not the old position 5');

    // Test 3: backspace at the start of Tail, directly under the card.
    final before =
        editor.state.document.blocks.map((b) => (b.type, b.content)).toList();
    editor.getBlockFocusNode(tailId).requestFocus();
    await frames(tester);
    editor.getBlockController(tailId).selection =
        const TextSelection.collapsed(offset: 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await frames(tester);

    final after = editor.state.document.blocks;
    expect(after.map((b) => (b.type, b.content)).toList(), before,
        reason: 'nothing changed');
    expect(editor.state.document.getBlockById(cardId)!.content, cardContent,
        reason: 'card content untouched');
    await drainSave(tester);
  });
}
