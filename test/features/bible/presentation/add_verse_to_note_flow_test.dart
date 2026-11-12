// "Add to notes" on a tapped verse, through the real reader screen and the real
// notes repository: pick a new note and the verse lands in its body with the
// title left alone; pick an existing note and the verse lands at its end.

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:notify/core/database/sync_database.dart';
import 'package:notify/core/sync/providers/sync_providers.dart';
import 'package:notify/core/theme/app_theme.dart';
import 'package:notify/features/bible/data/bible_repository.dart';
import 'package:notify/features/bible/domain/models/bible_book_entity.dart';
import 'package:notify/features/bible/domain/models/bible_reference.dart';
import 'package:notify/features/bible/domain/models/bible_verse_entity.dart';
import 'package:notify/features/bible/presentation/providers/bible_providers.dart';
import 'package:notify/features/bible/presentation/providers/verse_tag_providers.dart';
import 'package:notify/features/bible/presentation/screens/bible_chapter_screen.dart';
import 'package:notify/features/notes/domain/models/block_type.dart';
import 'package:notify/features/notes/domain/models/editor_block.dart';
import 'package:notify/features/notes/domain/models/editor_document.dart';
import 'package:notify/features/notes/domain/models/note.dart' as domain;
import 'package:notify/features/notes/presentation/providers/database_provider.dart';
import 'package:notify/l10n/app_localizations.dart';

class _FakeBibleRepo implements BibleRepository {
  @override
  BibleBookEntity? getBookById(int bookId) => const BibleBookEntity(
        id: 43,
        name: 'John',
        shortName: 'Jn',
        testament: 2,
        sortOrder: 43,
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  late SyncDatabase db;
  late ProviderContainer container;

  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    db = SyncDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      syncDatabaseProvider.overrideWithValue(db),
      currentUserIdProvider.overrideWith((ref) => 'user-1'),
      deviceIdProvider.overrideWith((ref) => 'device-1'),
      bibleRepositoryProvider.overrideWithValue(_FakeBibleRepo()),
      bibleTranslationsProvider.overrideWithValue(['NASB']),
      bibleVersesProvider.overrideWith((ref, p) => const [
            BibleVerseEntity(
              id: 1,
              translation: 'NASB',
              bookId: 43,
              chapter: 3,
              verse: 16,
              text: 'For God so loved the world',
            ),
          ]),
      bibleChaptersProvider.overrideWith((ref, p) => [3]),
      bibleBooksProvider.overrideWithValue([]),
      chapterVerseTagsProvider.overrideWith((ref, p) => <int, Set<String>>{}),
    ]);
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 150)));
    await tester.pump(const Duration(milliseconds: 100));
  }

  Future<void> openAddToNotes(WidgetTester tester) async {
    tester.view.physicalSize = const Size(402, 874) * 3;
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final router = GoRouter(routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => const BibleChapterScreen(
            bookId: 43, chapter: 3, initialTranslation: 'NASB'),
      ),
      GoRoute(
        path: '/notes/:id/edit',
        builder: (_, s) => Text('EDITOR ${s.pathParameters['id']}'),
      ),
    ]);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: AppTheme.light(),
        routerConfig: router,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ));
    await settle(tester);

    // Tap on the first line of the verse: the text is one paragraph, and the
    // middle of its box can fall in the blank end of its last line.
    await tester.tapAt(tester.getTopLeft(find.textContaining('For God so loved')) +
        const Offset(70, 10));
    for (var i = 0; i < 5; i++) {
      await settle(tester); // let the sheet finish sliding in
    }
    await tester.tap(find.text('Add to notes'));
    // The verse sheet closes, then the add-to-notes sheet slides in.
    for (var i = 0; i < 5; i++) {
      await settle(tester);
    }
  }

  Future<domain.Note> seedNote() async {
    final repo = container.read(notesRepositoryProvider);
    final note = domain.Note.create(id: 'n1', title: 'Sermon on grace')
        .copyWith(
      document: EditorDocument(blocks: [
        EditorBlock.paragraph().copyWith(content: 'Grace is a gift'),
      ]),
    );
    await repo.createNote(note);
    return note;
  }

  testWidgets('a new note gets the verse in its body, not its title',
      (tester) async {
    await openAddToNotes(tester);
    expect(find.text('New note'), findsOneWidget);

    await tester.tap(find.text('New note'));
    await settle(tester);
    await settle(tester);

    final notes = await tester.runAsync(
        () => container.read(notesRepositoryProvider).watchAllNotes().first);
    final note = notes!.single;
    expect(note.title, isEmpty, reason: 'the verse is not the title');

    final cards = note.document.blocks
        .where((b) => b.type == BlockType.bibleReference)
        .toList();
    expect(cards, hasLength(1));
    final ref = BibleReference.tryParseContent(cards.single.content)!;
    expect(ref.reference.book, 'John');
    expect(ref.reference.chapter, 3);
    expect(ref.reference.verses, [16]);
    expect(ref.reference.version, 'NASB');
    expect(note.document.blocks.last.type, BlockType.paragraph,
        reason: 'a line to keep typing on after the card');

    expect(find.text('EDITOR ${note.id}'), findsOneWidget,
        reason: 'the new note opens for editing');
  });

  testWidgets('an existing note gets the verse at its end', (tester) async {
    await tester.runAsync(seedNote);
    await openAddToNotes(tester);

    expect(find.text('Existing notes'), findsOneWidget);
    await tester.tap(find.text('Sermon on grace'));
    await settle(tester);
    await settle(tester);

    final note = (await tester.runAsync(
            () => container.read(notesRepositoryProvider).getNoteById('n1')))!;
    expect(note.title, 'Sermon on grace', reason: 'title untouched');
    final blocks = note.document.blocks;
    expect(blocks.first.content, 'Grace is a gift', reason: 'existing text kept');
    final card = blocks.lastWhere((b) => b.type == BlockType.bibleReference);
    expect(blocks.indexOf(card), greaterThan(0), reason: 'after the old text');
    expect(BibleReference.tryParseContent(card.content)!.reference.verses, [16]);

    expect(find.textContaining('Added to Sermon on grace'), findsOneWidget);
    expect(find.textContaining('EDITOR'), findsNothing,
        reason: 'it stays in the reader');
  });

  testWidgets('dismissing the sheet changes nothing', (tester) async {
    await tester.runAsync(seedNote);
    await openAddToNotes(tester);

    await tester.tapAt(const Offset(10, 10)); // the barrier
    await settle(tester);

    final notes = await tester.runAsync(
        () => container.read(notesRepositoryProvider).watchAllNotes().first);
    expect(notes!.single.document.blocks, hasLength(1));
  });
}
