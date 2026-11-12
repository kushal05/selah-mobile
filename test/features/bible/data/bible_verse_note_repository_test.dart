// Notes written on a verse: any number per verse, newest first, found by the
// verse they cover, and each write is one transaction of the row and its
// oplog entry.

import 'dart:convert';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:notify/core/database/sync_database.dart';
import 'package:notify/features/bible/data/bible_verse_note_repository.dart';

void main() {
  late SyncDatabase db;
  late BibleVerseNoteRepository repo;

  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  setUp(() {
    db = SyncDatabase.forTesting(NativeDatabase.memory());
    repo = BibleVerseNoteRepository(db, 'device-1', 'user-1');
  });

  tearDown(() => db.close());

  Future<List<String>> notesOn(int book, int chapter, int verse) async {
    final list = await repo
        .watchNotesForVerse(bookId: book, chapter: chapter, verse: verse)
        .first;
    return list.map((n) => n.content).toList();
  }

  test('a verse can have several notes, newest first', () async {
    await repo.addNote(bookId: 43, chapter: 3, verse: 16, content: 'first');
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await repo.addNote(bookId: 43, chapter: 3, verse: 16, content: 'second');

    expect(await notesOn(43, 3, 16), ['second', 'first']);
  });

  test('notes belong to their verse, chapter and book only', () async {
    await repo.addNote(bookId: 43, chapter: 3, verse: 16, content: 'here');

    expect(await notesOn(43, 3, 17), isEmpty);
    expect(await notesOn(43, 4, 16), isEmpty);
    expect(await notesOn(44, 3, 16), isEmpty);
  });

  test('a note over a range is found from every verse in it', () async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.into(db.bibleVerseNotes).insert(BibleVerseNotesCompanion.insert(
          id: 'range',
          bookId: 43,
          chapter: 3,
          verseStart: 14,
          verseEnd: 17,
          content: 'ranged',
          createdAt: now,
          updatedAt: now,
        ));

    expect(await notesOn(43, 3, 14), ['ranged']);
    expect(await notesOn(43, 3, 16), ['ranged']);
    expect(await notesOn(43, 3, 17), ['ranged']);
    expect(await notesOn(43, 3, 18), isEmpty);
  });

  test('a deleted note is not listed', () async {
    final n = await repo.addNote(
        bookId: 43, chapter: 3, verse: 16, content: 'gone');
    await (db.update(db.bibleVerseNotes)..where((t) => t.id.equals(n.id)))
        .write(const BibleVerseNotesCompanion(deleted: Value(1)));

    expect(await notesOn(43, 3, 16), isEmpty);
  });

  test('saving writes the row and one INSERT oplog entry together', () async {
    final n = await repo.addNote(
        bookId: 43, chapter: 3, verse: 16, content: 'kept');

    final rows = await db.select(db.bibleVerseNotes).get();
    expect(rows, hasLength(1));
    expect(rows.single.userId, 'user-1');
    expect(rows.single.version, 1);

    final ops = await db.select(db.oplog).get();
    expect(ops, hasLength(1));
    expect(ops.single.entityType, 'bible_verse_note');
    expect(ops.single.operation, 'INSERT');
    expect(ops.single.entityId, n.id);
    expect(ops.single.deviceId, 'device-1');
    final payload = jsonDecode(ops.single.payloadJson) as Map<String, dynamic>;
    expect(payload['content'], 'kept');
    expect(payload['verseStart'], 16);
  });

  test('is wiped with the rest of the user data', () async {
    await repo.addNote(bookId: 43, chapter: 3, verse: 16, content: 'mine');
    await db.clearAllUserData();
    expect(await db.select(db.bibleVerseNotes).get(), isEmpty);
  });

  test('a note written on several verses is found from each of them', () async {
    final n = await repo.addNote(
        bookId: 43, chapter: 3, verse: 14, verseEnd: 17, content: 'group');

    expect([n.verseStart, n.verseEnd], [14, 17]);
    for (final v in [14, 15, 16, 17]) {
      expect(await notesOn(43, 3, v), ['group']);
    }
    expect(await notesOn(43, 3, 13), isEmpty);
    expect(await notesOn(43, 3, 18), isEmpty);
  });

  test('a note written on a single verse covers only that verse', () async {
    final n = await repo.addNote(bookId: 43, chapter: 3, verse: 16, content: 'one');
    expect([n.verseStart, n.verseEnd], [16, 16]);
  });

  test('the chapter stream lists every note in it, newest first', () async {
    await repo.addNote(bookId: 43, chapter: 3, verse: 1, content: 'a');
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await repo.addNote(
        bookId: 43, chapter: 3, verse: 2, verseEnd: 4, content: 'b');
    await repo.addNote(bookId: 43, chapter: 4, verse: 1, content: 'other');

    final list =
        await repo.watchNotesForChapter(bookId: 43, chapter: 3).first;
    expect(list.map((n) => n.content), ['b', 'a']);
  });
}
