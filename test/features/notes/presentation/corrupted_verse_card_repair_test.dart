// A note whose Bible card had the next line's text appended to it (an earlier
// backspace bug) must come back with the card restored and the stray text as
// the line under it — not as a blank card (no book, 1:1, KJV) that traps the
// cursor at the end of the note.

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

  testWidgets('reopening a corrupted card restores it and the stray text',
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
    editor.updateTitle('Corrupted');
    final firstId = editor.state.document.blocks.first.id;
    editor.updateBlockContent(firstId, 'Hello');
    editor.getBlockController(firstId).text = 'Hello';
    editor.ensureBibleReferenceTriggeredBlock();
    editor.insertBibleReferenceBlock(
        book: 'John', chapter: 3, verses: const [16], version: 'NASB');
    await frames(tester);

    // What the old merge did: the text below went into the card's content.
    final card = editor.state.document.blocks
        .firstWhere((b) => b.type == BlockType.bibleReference);
    editor.updateBlockContent(card.id, '${card.content}Tail');
    await tester.runAsync(editor.forceSave);
    await tester.pump(const Duration(seconds: 2));

    final rows = await db.select(db.syncNotes).get();
    expect(rows, hasLength(1), reason: 'precondition: note saved');
    final noteId = rows.single.id;
    expect(BibleReference.tryParseContent('${card.content}Tail'), isNotNull);

    // Reopen from the database.
    final keepAlive =
        container.listen(noteEditorProvider(noteId), (_, _) {});
    addTearDown(keepAlive.close);
    final reopened = container.read(noteEditorProvider(noteId).notifier);
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 500)));
    await tester.pump();

    final blocks = reopened.state.document.blocks;
    final restored = blocks.firstWhere((b) => b.type == BlockType.bibleReference);
    final ref = BibleReference.fromJson(
        jsonDecode(restored.content) as Map<String, dynamic>);
    expect(ref.reference.book, 'John');
    expect(ref.reference.chapter, 3);
    expect(ref.reference.verses, [16]);
    expect(ref.reference.version.toLowerCase(), 'nasb',
        reason: 'the version the card had, not the KJV fallback');

    final idx = blocks.indexOf(restored);
    expect(blocks[idx + 1].type, BlockType.paragraph);
    expect(blocks[idx + 1].content, contains('Tail'),
        reason: 'the stray text becomes the line under the card, so there is '
            'a line to type on after the card');

    await tester.pump(const Duration(seconds: 3));
  });
}
