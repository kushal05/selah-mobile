// A highlight over several verses: the plan from the selection is written in
// one go, and only the selected verses change.

import 'dart:convert';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:notify/core/database/sync_database.dart';
import 'package:notify/features/bible/data/bible_highlight_repository.dart';
import 'package:notify/features/bible/data/bible_verse_note_repository.dart';
import 'package:notify/features/bible/domain/models/bible_highlight_entity.dart';
import 'package:notify/features/bible/domain/models/bible_verse_note_entity.dart';
import 'package:notify/features/bible/domain/services/verse_selection.dart';

void main() {
  late SyncDatabase db;
  late BibleHighlightRepository repo;
  late BibleVerseNoteRepository notes;

  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  setUp(() {
    db = SyncDatabase.forTesting(NativeDatabase.memory());
    repo = BibleHighlightRepository(db, 'device-1', 'user-1');
    notes = BibleVerseNoteRepository(db, 'device-1', 'user-1');
  });
  tearDown(() => db.close());

  Future<List<BibleHighlightEntity>> all() =>
      repo.getHighlightsForChapter(bookId: 1, chapter: 1);

  Future<void> apply(Set<int> verses, HighlightColor? color) async {
    final plan =
        planHighlight(existing: await all(), selected: verses, color: color);
    await repo.applyPlan(plan, bookId: 1, chapter: 1, notes: notes);
  }

  Map<int, HighlightColor> byVerse(List<BibleHighlightEntity> hs) => {
        for (final h in hs)
          for (var v = h.verseStart; v <= h.verseEnd; v++) v: h.color,
      };

  test('highlighting three verses writes one highlight over them', () async {
    await apply({3, 4, 5}, HighlightColor.blue);
    final hs = await all();
    expect(hs.length, 1);
    expect([hs.single.verseStart, hs.single.verseEnd], [3, 5]);
  });

  test('a split leaves the other verses as they were', () async {
    await apply({2, 3, 4, 5, 6, 7}, HighlightColor.yellow);
    await apply({4, 5}, HighlightColor.pink);

    expect(byVerse(await all()), {
      2: HighlightColor.yellow,
      3: HighlightColor.yellow,
      4: HighlightColor.pink,
      5: HighlightColor.pink,
      6: HighlightColor.yellow,
      7: HighlightColor.yellow,
    });
  });

  test('removing from the middle leaves both ends highlighted', () async {
    await apply({2, 3, 4, 5, 6}, HighlightColor.green);
    await apply({4}, null);

    expect(byVerse(await all()).keys.toSet(), {2, 3, 5, 6});
  });

  test('choosing the colour a highlight already has changes nothing',
      () async {
    await apply({1, 2, 3, 4, 5}, HighlightColor.green);
    final before = (await db.select(db.oplog).get()).length;

    await apply({3}, HighlightColor.green);

    final hs = await all();
    expect(hs.length, 1, reason: 'not cut into three');
    expect([hs.single.verseStart, hs.single.verseEnd], [1, 5]);
    expect((await db.select(db.oplog).get()).length, before);
  });

  test('a selection half in a colour only writes the verses that need it',
      () async {
    await apply({2, 3}, HighlightColor.green);
    await apply({3, 4, 5}, HighlightColor.green);

    expect(byVerse(await all()).keys.toSet(), {2, 3, 4, 5});
    expect((await all()).length, 2,
        reason: '3 stays in the old one; 4-5 is new, with no overlap');
  });

  test('each write is in the oplog with the right range and version',
      () async {
    await apply({2, 3, 4}, HighlightColor.green);
    await apply({3}, HighlightColor.blue);

    final ops = await db.select(db.oplog).get();
    // insert; then trim to 2-2, add 4-4 (right piece) and 3-3 (the middle).
    expect(ops.length, 4);
    final payloads = [for (final o in ops) jsonDecode(o.payloadJson)];
    final update = ops.indexWhere((o) => o.operation == 'UPDATE');
    expect(payloads[update]['verseStart'], 2);
    expect(payloads[update]['verseEnd'], 2);
    expect(payloads[update]['version'], 2,
        reason: 'the trimmed highlight moves to the next version');
    final ranges = {
      for (final p in payloads.where((p) => p['version'] == 1))
        '${p['verseStart']}-${p['verseEnd']}',
    };
    expect(ranges, containsAll(['2-4', '4-4', '3-3']));
  });

  test('a note on a highlight that is removed is kept as a verse note, in '
      'the same transaction', () async {
    final h = await repo.createHighlight(
        bookId: 1,
        chapter: 1,
        verseStart: 3,
        verseEnd: 4,
        color: HighlightColor.green,
        note: 'written long ago');

    await apply({3, 4}, null);

    expect(await all(), isEmpty);
    final kept = await notes.watchNotesForChapter(bookId: 1, chapter: 1).first;
    expect(kept.single.content, 'written long ago');
    expect([kept.single.verseStart, kept.single.verseEnd], [3, 4]);
    expect(h.id, isNotEmpty);
  });

  test('if saving the kept note fails, the highlight is not removed',
      () async {
    await repo.createHighlight(
        bookId: 1,
        chapter: 1,
        verseStart: 3,
        verseEnd: 4,
        color: HighlightColor.green,
        note: 'precious');
    final failing = _FailingNotes(db);

    final plan = planHighlight(
        existing: await all(), selected: {3, 4}, color: null);
    await expectLater(
        repo.applyPlan(plan, bookId: 1, chapter: 1, notes: failing),
        throwsA(isA<StateError>()));

    final hs = await all();
    expect(hs.length, 1, reason: 'rolled back with the failed note');
    expect(hs.single.note, 'precious');
  });
}

class _FailingNotes extends BibleVerseNoteRepository {
  _FailingNotes(SyncDatabase db) : super(db, 'device-1', 'user-1');

  @override
  Future<BibleVerseNoteEntity> addNote({
    required int bookId,
    required int chapter,
    required int verse,
    int? verseEnd,
    required String content,
  }) async =>
      throw StateError('disk full');
}
