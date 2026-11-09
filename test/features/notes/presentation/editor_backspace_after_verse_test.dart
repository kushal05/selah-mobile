// Backspace at the start of a line directly under a Bible card.
//
// The card has no text to merge into and no field to hold a caret. An empty
// line under it is removed and the caret goes to the end of the nearest text
// line above; a line with text is left alone; the card is never altered.
// Paragraph merge and the list-item convert-to-paragraph step are checked too.

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

const _line = 'A line of the note';

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

  Future<NoteEditorNotifier> openEditor(WidgetTester tester) async {
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: NoteEditorScreen(),
      ),
    ));
    await frames(tester);
    return container.read(noteEditorProvider(null).notifier);
  }

  /// [line][John 3:16 card][empty line].
  Future<NoteEditorNotifier> lineCardEmpty(WidgetTester tester) async {
    final editor = await openEditor(tester);
    final first = editor.state.document.blocks.first.id;
    editor.updateBlockContent(first, _line);
    editor.getBlockController(first).text = _line;
    editor.ensureBibleReferenceTriggeredBlock();
    editor.insertBibleReferenceBlock(
        book: 'John', chapter: 3, verses: const [16], version: 'KJV');
    await frames(tester);
    final types = editor.state.document.blocks.map((b) => b.type).toList();
    expect(types, [
      BlockType.paragraph,
      BlockType.bibleReference,
      BlockType.paragraph,
    ], reason: 'precondition');
    return editor;
  }

  testWidgets(
      'backspace in an empty line under a card goes to the end of the line '
      'above the card', (tester) async {
    final editor = await lineCardEmpty(tester);
    final blocks = editor.state.document.blocks;
    final firstId = blocks[0].id;
    final cardContent = blocks[1].content;
    final emptyId = blocks[2].id;
    editor.getBlockFocusNode(emptyId).requestFocus();
    await frames(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await frames(tester);

    final after = editor.state.document.blocks;
    expect(after.map((b) => b.type),
        [BlockType.paragraph, BlockType.bibleReference]);
    expect(after[1].content, cardContent, reason: 'card untouched');
    expect(editor.getBlockFocusNode(firstId).hasFocus, isTrue);
    expect(editor.getBlockController(firstId).selection,
        const TextSelection.collapsed(offset: _line.length));
    await drainSave(tester);
  });

  testWidgets(
      'backspace at the start of a line with text under a card changes '
      'nothing', (tester) async {
    final editor = await lineCardEmpty(tester);
    final emptyId = editor.state.document.blocks[2].id;
    editor.updateBlockContent(emptyId, 'Below');
    editor.getBlockController(emptyId).text = 'Below';
    await frames(tester);
    editor.getBlockFocusNode(emptyId).requestFocus();
    await frames(tester);
    editor.getBlockController(emptyId).selection =
        const TextSelection.collapsed(offset: 0);
    final before = editor.state.document.blocks.map((b) => b.content).toList();

    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await frames(tester);

    expect(
        editor.state.document.blocks.map((b) => b.content).toList(), before);
    await drainSave(tester);
  });

  testWidgets('mergeWithPreviousBlock with a card above drops an empty line',
      (tester) async {
    final editor = await lineCardEmpty(tester);
    final emptyId = editor.state.document.blocks[2].id;
    editor.mergeWithPreviousBlock(emptyId);
    await frames(tester);
    expect(editor.state.document.getBlockById(emptyId), isNull);
    expect(editor.state.document.blocks.length, 2);
    await drainSave(tester);
  });

  testWidgets('paragraph merges into the paragraph above', (tester) async {
    final editor = await openEditor(tester);
    final firstId = editor.state.document.blocks.first.id;
    editor.updateBlockContent(firstId, 'OneTwo');
    editor.getBlockController(firstId).text = 'OneTwo';
    editor.splitBlock(firstId, 3);
    await frames(tester);
    final secondId = editor.state.document.blocks[1].id;

    editor.mergeWithPreviousBlock(secondId);
    await frames(tester);

    expect(editor.state.document.blocks.length, 1);
    expect(editor.state.document.blocks.first.content, 'OneTwo');
    await drainSave(tester);
  });

  testWidgets('top-level list item converts to a paragraph first',
      (tester) async {
    final editor = await openEditor(tester);
    final firstId = editor.state.document.blocks.first.id;
    editor.updateBlockContent(firstId, 'OneTwo');
    editor.getBlockController(firstId).text = 'OneTwo';
    editor.splitBlock(firstId, 3);
    await frames(tester);
    final secondId = editor.state.document.blocks[1].id;
    editor.changeBlockType(secondId, BlockType.bulletList);
    await frames(tester);

    editor.mergeWithPreviousBlock(secondId);
    await frames(tester);

    final blocks = editor.state.document.blocks;
    expect(blocks.length, 2, reason: 'not merged yet');
    expect(blocks[1].type, BlockType.paragraph);
    expect(blocks[1].content, 'Two');
    await drainSave(tester);
  });
}
