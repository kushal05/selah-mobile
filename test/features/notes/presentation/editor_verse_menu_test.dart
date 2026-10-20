// A verse's ⋮ menu inside the real note editor.
//
// Two things the menu does that only show up in the editor itself: removing
// a verse must not focus a line and pull the keyboard up (the Backspace caret
// fix had been placed in the deletion both share), and Change version must
// exist — the widget had the item and its picker, but the editor never passed
// the callback that shows it.

import 'dart:convert';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:notify/core/database/sync_database.dart';
import 'package:notify/core/sync/providers/sync_providers.dart';
import 'package:notify/features/bible/domain/models/bible_reference.dart';
import 'package:notify/features/bible/presentation/providers/bible_providers.dart';
import 'package:notify/features/notes/domain/models/block_type.dart';
import 'package:notify/features/notes/presentation/providers/note_editor_provider.dart';
import 'package:notify/features/notes/presentation/screens/note_editor_screen.dart';
import 'package:notify/features/notes/presentation/widgets/editor/bible_reference_block_widget.dart';
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
      bibleTranslationsProvider.overrideWithValue(const ['KJV', 'NKJV']),
      verseLookupProvider.overrideWith((ref, verseRef) =>
          [const BibleVerseText(verse: 16, content: 'For God so loved the world')]),
    ]);
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  /// Bounded pumping: in the editor a focused field's caret blinks forever,
  /// so pumpAndSettle never settles.
  Future<void> frames(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  /// The editor with a line of text and John 3:16 (KJV) under it.
  Future<NoteEditorNotifier> editorWithVerse(WidgetTester tester) async {
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
    final first = editor.state.document.blocks.first.id;
    editor.updateBlockContent(first, 'A line of the note');
    editor.ensureBibleReferenceTriggeredBlock();
    editor.insertBibleReferenceBlock(
        book: 'John', chapter: 3, verses: const [16], version: 'KJV');
    await frames(tester);
    expect(find.byType(BibleReferenceBlockWidget), findsOneWidget,
        reason: 'precondition: the verse is in the note');
    return editor;
  }

  Future<void> openMenu(WidgetTester tester) async {
    await tester.tap(find.descendant(
        of: find.byType(BibleReferenceBlockWidget),
        matching: find.byIcon(Icons.more_vert_rounded)));
    await frames(tester);
  }

  Future<void> drainSave(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 2));
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pump(const Duration(seconds: 2));
  }

  Iterable<Map<String, dynamic>> verses(NoteEditorNotifier editor) =>
      editor.state.document.blocks
          .where((b) => b.type == BlockType.bibleReference)
          .map((b) => jsonDecode(b.content) as Map<String, dynamic>);

  testWidgets('removing a verse does not focus a line or raise the keyboard',
      (tester) async {
    final editor = await editorWithVerse(tester);
    FocusManager.instance.primaryFocus?.unfocus();
    await frames(tester);

    await openMenu(tester);
    await tester.tap(find.text('Remove reference'));
    await frames(tester);

    expect(verses(editor), isEmpty, reason: 'precondition: removed');
    for (final b in editor.state.document.blocks) {
      expect(editor.getBlockFocusNode(b.id).hasFocus, isFalse,
          reason: 'nothing asked for a line to be focused');
    }
    await drainSave(tester);
  });

  testWidgets('Change version switches the verse to another translation',
      (tester) async {
    final editor = await editorWithVerse(tester);
    await openMenu(tester);
    await tester.tap(find.text('Change version'));
    await frames(tester);
    await tester.tap(find.text('NKJV'));
    await frames(tester);

    final verse = verses(editor).single;
    expect((verse['reference'] as Map)['version'], 'NKJV');
    expect((verse['reference'] as Map)['verses'], [16],
        reason: 'the same verses, only the translation changed');
    await drainSave(tester);
  });
}
