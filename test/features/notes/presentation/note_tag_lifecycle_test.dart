// The note's tags are the ones chosen by hand plus the ones its own content
// implies: `#faith` in the text, and tags put on a Bible reference block.
//
// Derived tags are recomputed from the document on every save rather than
// remembered. That is what makes deleting `#faith` remove the tag — the name
// is simply no longer there to derive — while a tag that is also manual, or
// also on a verse, survives the text going away.

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:notify/core/database/sync_database.dart';
import 'package:notify/core/sync/providers/sync_providers.dart';
import 'package:notify/features/notes/domain/models/block_type.dart';
import 'package:notify/features/notes/presentation/providers/note_editor_provider.dart';

const _userId = 'test-user';

void main() {
  late SyncDatabase db;
  late ProviderContainer container;

  setUpAll(() {
    // insertBibleReferenceBlock schedules a focus callback on the binding.
    TestWidgetsFlutterBinding.ensureInitialized();
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  setUp(() {
    db = SyncDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(overrides: [
      syncDatabaseProvider.overrideWithValue(db),
      currentUserIdProvider.overrideWith((ref) => _userId),
      deviceIdProvider.overrideWith((ref) => 'test-device'),
    ]);
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  NoteEditorNotifier editor() =>
      container.read(noteEditorProvider(null).notifier);

  /// The first block you can type in. Inserting a Bible block shifts the
  /// order, so `blocks.first` is not reliably the paragraph.
  String firstTextBlock(NoteEditorNotifier n) => n.state.document.blocks
      .firstWhere((b) => b.type != BlockType.bibleReference)
      .id;

  /// Names of the tags the note would be saved with.
  Future<Set<String>> effectiveNames(NoteEditorNotifier n) async {
    final ids = await n.effectiveTagIds();
    final repo = container.read(tagRepositoryProvider);
    final names = <String>{};
    for (final id in ids) {
      final tag = await repo.getTagById(id);
      if (tag != null) names.add(tag.name);
    }
    return names;
  }

  /// Adds a Bible reference block through the path the app uses: typing `@`
  /// arms the picker, and the picker's result inserts the block. Returns its
  /// block id.
  String addBibleBlock(NoteEditorNotifier n) {
    final before = n.state.document.blocks.map((b) => b.id).toSet();
    n.updateBlockContent(n.state.document.blocks.first.id, '@');
    n.insertBibleReferenceBlock(
      book: 'John',
      chapter: 3,
      verses: const [16],
      version: 'nkjv',
    );
    return n.state.document.blocks
        .firstWhere((b) =>
            b.type == BlockType.bibleReference && !before.contains(b.id))
        .id;
  }

  test('a #tag in the text becomes a tag on the note', () async {
    final n = editor();
    n.updateBlockContent(n.state.document.blocks.first.id, 'trusting #faith');

    expect(await effectiveNames(n), {'faith'});
  });

  test('#Faith and #faith are the same tag', () async {
    final n = editor();
    n.updateBlockContent(
        n.state.document.blocks.first.id, '#Faith and #faith');

    final ids = await n.effectiveTagIds();
    expect(ids, hasLength(1));
    expect(await effectiveNames(n), {'faith'});
  });

  test('deleting the text removes the tag', () async {
    final n = editor();
    final blockId = n.state.document.blocks.first.id;
    n.updateBlockContent(blockId, 'trusting #faith');
    expect(await effectiveNames(n), {'faith'});

    n.updateBlockContent(blockId, 'trusting');

    expect(await effectiveNames(n), isEmpty,
        reason: 'the name is no longer in the text to derive');
  });

  test('a tag that is also manual survives the text going away', () async {
    final n = editor();
    final blockId = n.state.document.blocks.first.id;
    n.updateBlockContent(blockId, '#faith');
    final repo = container.read(tagRepositoryProvider);
    final faith = await repo.getOrCreateTag('faith', _userId);
    n.setTags([faith.id]);

    n.updateBlockContent(blockId, 'nothing here');

    expect(await effectiveNames(n), {'faith'});
  });

  test('tags on a Bible reference block land on the note', () async {
    final repo = container.read(tagRepositoryProvider);
    final grace = await repo.getOrCreateTag('grace', _userId);

    final n = editor();
    final blockId = addBibleBlock(n);
    n.updateBibleReferenceTags(blockId: blockId, tagIds: [grace.id]);

    expect(await effectiveNames(n), {'grace'});
  });

  test('a Bible block whose JSON is broken contributes nothing, not a crash',
      () async {
    final n = editor();
    final blockId = addBibleBlock(n);
    // Corrupt it the way a bad sync payload would.
    n.updateBlockContent(blockId, 'not json at all');

    expect(await effectiveNames(n), isEmpty);
  });

  test('inline, verse and manual tags all come through together', () async {
    final repo = container.read(tagRepositoryProvider);
    final grace = await repo.getOrCreateTag('grace', _userId);
    final hope = await repo.getOrCreateTag('hope', _userId);

    final n = editor();
    final blockId = addBibleBlock(n);
    n.updateBibleReferenceTags(blockId: blockId, tagIds: [grace.id]);
    n.updateBlockContent(firstTextBlock(n), 'see #faith');
    n.setTags([hope.id]);

    expect(await effectiveNames(n), {'faith', 'grace', 'hope'});
  });

  test('a # inside a word is not a tag', () async {
    final n = editor();
    n.updateBlockContent(
        n.state.document.blocks.first.id, 'see example.com#section');

    expect(await effectiveNames(n), isEmpty);
  });

  group('when a tag is created', () {
    Future<List<String>> allTagNames() async {
      final tags =
          await container.read(tagRepositoryProvider).getAllTags(_userId);
      return tags.map((t) => t.name).toList();
    }

    test('typing does not create a tag for every half-typed word', () async {
      // The autosave fires a third of a second after the last keystroke,
      // which is an ordinary pause in the middle of a word. Creating then
      // turned "#faith" into four tags — f, fa, fai, faith — and left them
      // there forever.
      final n = editor();
      final id = n.state.document.blocks.first.id;

      for (final partial in ['#f', '#fa', '#fai', '#faith']) {
        n.updateBlockContent(id, partial);
        await n.effectiveTagIds(create: false); // what an autosave does
      }

      expect(await allTagNames(), isEmpty);
    });

    test('leaving the note creates it', () async {
      final n = editor();
      n.updateBlockContent(n.state.document.blocks.first.id, '#faith');

      await n.effectiveTagIds(create: true); // what forceSave does

      expect(await allTagNames(), ['faith']);
    });

    test('an autosave still attaches a tag that already exists', () async {
      final repo = container.read(tagRepositoryProvider);
      await repo.getOrCreateTag('faith', _userId);

      final n = editor();
      n.updateBlockContent(n.state.document.blocks.first.id, '#faith');

      final ids = await n.effectiveTagIds(create: false);

      expect(ids, hasLength(1),
          reason: 'an existing tag should attach without waiting');
      expect(await allTagNames(), ['faith']);
    });
  });
}
