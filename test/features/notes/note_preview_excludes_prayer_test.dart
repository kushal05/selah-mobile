// A note's prayer never shows in the notes list's preview.
//
// A note has three sections — main, personal application and prayer — and the
// list previews only the first non-empty block of the main one. That holds only
// if every block still carries its section by the time the list reads it, and
// the list reads notes two ways: decoded from the document_json snapshot, or,
// when a note has none (one that arrived by sync before a local save), rebuilt
// from the note_blocks table. A path that dropped the tag would default the
// prayer to main and put it in the preview. Both paths are driven here through
// the app's real repository over a real database, and then the real screen.

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:notify/core/database/sync_database.dart';
import 'package:notify/core/sync/providers/sync_providers.dart';
import 'package:notify/core/theme/app_theme.dart';
import 'package:notify/features/notes/domain/models/editor_block.dart';
import 'package:notify/features/notes/domain/models/editor_document.dart';
import 'package:notify/features/notes/domain/models/note.dart' as domain;
import 'package:notify/features/notes/domain/models/note_section.dart';
import 'package:notify/features/notes/presentation/providers/database_provider.dart';
import 'package:notify/features/notes/presentation/screens/notes_home_screen.dart';
import 'package:notify/l10n/l10n.dart';

const _main = 'Grace is a gift, not a wage';
const _prayer = 'Lord, teach me to receive what I cannot earn';

EditorBlock _block(NoteSection section, String text) =>
    EditorBlock.paragraph(section: section).copyWith(content: text);

domain.Note _note(String id, List<EditorBlock> blocks) =>
    domain.Note.create(id: id, title: 'Sermon $id')
        .copyWith(document: EditorDocument(blocks: blocks));

/// The text of the main section's first non-empty block — what the list shows.
String? _previewOf(domain.Note n) => n.document
    .getBlocksForSection(NoteSection.main)
    .map((b) => b.content)
    .where((c) => c.trim().isNotEmpty)
    .firstOrNull;

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  group('a saved note keeps its prayer out of the main section', () {
    late SyncDatabase db;
    late ProviderContainer c;

    setUp(() {
      db = SyncDatabase.forTesting(NativeDatabase.memory());
      c = ProviderContainer(overrides: [
        syncDatabaseProvider.overrideWithValue(db),
        currentUserIdProvider.overrideWith((ref) => 'u1'),
      ]);
    });
    tearDown(() async {
      c.dispose();
      await db.close();
    });

    Future<domain.Note> saveAndReadBack() async {
      final repo = c.read(notesRepositoryProvider);
      await repo.createNote(_note('n1', [
        _block(NoteSection.main, _main),
        _block(NoteSection.prayer, _prayer),
      ]));
      final notes = await repo.watchAllNotes().first;
      return notes.singleWhere((n) => n.id == 'n1');
    }

    test('read from the document snapshot', () async {
      final note = await saveAndReadBack();

      expect(_previewOf(note), _main);
      final prayerBlocks = note.document.getBlocksForSection(NoteSection.prayer);
      expect(prayerBlocks.map((b) => b.content), [_prayer],
          reason: 'the prayer must still be tagged as prayer');
    });

    test('and rebuilt from the blocks table, with no snapshot', () async {
      // The other path the list takes: a note with no document_json, as one
      // can be after arriving by sync. Rebuilt from note_blocks instead.
      await saveAndReadBack();
      await db.customStatement(
          "UPDATE sync_notes SET document_json = NULL WHERE id = 'n1'");

      final notes =
          await c.read(notesRepositoryProvider).watchAllNotes().first;
      final note = notes.singleWhere((n) => n.id == 'n1');

      expect(_previewOf(note), _main);
      expect(
        note.document.getBlocksForSection(NoteSection.prayer).map((b) => b.content),
        [_prayer],
      );
    });
  });

  group('the notes list', () {
    Future<void> pumpWith(WidgetTester tester, List<domain.Note> notes) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          notesStreamProvider.overrideWith((ref) => Stream.value(notes)),
          noteFoldersStreamProvider.overrideWith((ref) => Stream.value(const [])),
          peopleStreamProvider.overrideWith((ref) => Stream.value(const [])),
          tagsStreamProvider.overrideWith((ref) => Stream.value(const [])),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const NotesHomeScreen(),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
    }

    Finder anywhere(String s) => find.textContaining(s, findRichText: true);

    testWidgets('previews the main text, not the prayer', (tester) async {
      await pumpWith(tester, [
        _note('n1', [
          _block(NoteSection.main, _main),
          _block(NoteSection.prayer, _prayer),
        ]),
      ]);

      expect(anywhere('Sermon n1'), findsWidgets, reason: 'the row is there');
      expect(anywhere(_main), findsWidgets);
      expect(anywhere(_prayer), findsNothing,
          reason: "the note's prayer must not appear in the list");
    });

    testWidgets('and shows no prayer even when the main section is empty',
        (tester) async {
      // The case most likely to leak: with nothing in main, a preview that
      // reached past it would find the prayer next.
      await pumpWith(tester, [
        _note('n2', [
          _block(NoteSection.main, ''),
          _block(NoteSection.prayer, _prayer),
        ]),
      ]);

      expect(anywhere('Sermon n2'), findsWidgets);
      expect(anywhere(_prayer), findsNothing);
    });
  });
}
