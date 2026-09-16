// The verse-tag index is a whole-library scan over Bible reference blocks.
// Drift re-runs a watched query on any write to note_blocks, so typing in an
// unrelated note re-emitted the entire list — measured at one emission per
// keystroke-pause save — and the index decoded every block's JSON again.

import 'package:drift/drift.dart' show driftRuntimeOptions, Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:notify/core/database/sync_database.dart';
import 'package:notify/core/sync/providers/sync_providers.dart';
import 'package:notify/features/bible/presentation/providers/verse_tag_providers.dart';

void main() {
  late SyncDatabase db;
  late ProviderContainer container;

  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  setUp(() {
    db = SyncDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(overrides: [
      syncDatabaseProvider.overrideWithValue(db),
      currentUserIdProvider.overrideWith((ref) => 'u'),
      deviceIdProvider.overrideWith((ref) => 'd'),
    ]);
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  Future<void> writeParagraph(int i) => db
      .into(db.noteBlocks)
      .insertOnConflictUpdate(NoteBlocksCompanion(
        id: Value('p$i'),
        noteId: const Value('n1'),
        blockType: const Value('paragraph'),
        contentJson: Value('{"text":"typing $i"}'),
        orderIndex: Value(i),
        updatedAt: const Value(0),
        createdAt: const Value(0),
        section: const Value('main'),
      ));

  test('typing in an unrelated note does not rebuild the index', () async {
    var rebuilds = 0;
    final sub = container.listen(
      verseTagsProvider,
      (_, next) {
        if (next.hasValue) rebuilds++;
      },
      fireImmediately: true,
    );
    addTearDown(sub.close);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    final baseline = rebuilds;

    for (var i = 0; i < 3; i++) {
      await writeParagraph(i);
      await Future<void>.delayed(const Duration(milliseconds: 30));
    }

    expect(rebuilds, baseline,
        reason: 'three unrelated paragraph writes rebuilt the whole index');
  });

  test('the index is dropped when nothing is reading it', () async {
    final sub = container.listen(verseTagsProvider, (_, _) {});
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(container.exists(verseTagsProvider), isTrue);

    sub.close();
    await Future<void>.delayed(const Duration(milliseconds: 60));

    expect(container.exists(verseTagsProvider), isFalse,
        reason: 'a whole-library scan should not outlive the reader');
  });
}
