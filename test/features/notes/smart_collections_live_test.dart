// The smart collections follow edits, and a chosen one never shows every note.
//
// They were one-shot queries behind cached FutureProviders that nothing
// invalidated. Tag a note and it stayed under Untagged; write one and it never
// reached Recently Edited — for the rest of the session. They are live queries
// now, against the real database here, not a fake: whether drift re-runs a
// query depends on the tables it was told the query reads, and only a real
// database exercises that.
//
// Each test holds ONE subscription open across the edit. That matters: these
// providers are autoDispose, so letting go and reading again starts a fresh
// query, which would find the new state even with the bug — and the test would
// prove nothing. The update has to arrive on the subscription already open.

import 'dart:async';

import 'package:drift/drift.dart'
    show
        ApplyInterceptor,
        QueryExecutor,
        QueryInterceptor,
        Variable,
        driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:notify/core/database/sync_database.dart';
import 'package:notify/core/sync/providers/sync_providers.dart';
import 'package:notify/features/notes/domain/models/note.dart' as domain;
import 'package:notify/features/notes/presentation/providers/database_provider.dart';
import 'package:notify/features/notes/presentation/providers/notes_home_ui_state.dart';
import 'package:notify/features/notes/presentation/providers/smart_collection.dart';
import 'package:notify/features/notes/presentation/providers/visible_notes_provider.dart';

/// A container over a fresh in-memory database, signed in as `u1`.
(ProviderContainer, SyncDatabase) _live() {
  final db = SyncDatabase.forTesting(NativeDatabase.memory());
  final c = ProviderContainer(overrides: [
    syncDatabaseProvider.overrideWithValue(db),
    currentUserIdProvider.overrideWith((ref) => 'u1'),
  ]);
  addTearDown(c.dispose);
  addTearDown(db.close);
  return (c, db);
}

/// Records every SELECT the database actually runs.
class _Selects extends QueryInterceptor {
  final sql = <String>[];

  @override
  Future<List<Map<String, Object?>>> runSelect(
      QueryExecutor executor, String statement, List<Object?> args) {
    sql.add(statement);
    return super.runSelect(executor, statement, args);
  }
}

(ProviderContainer, SyncDatabase, _Selects) _watched() {
  final selects = _Selects();
  final db = SyncDatabase.forTesting(
      NativeDatabase.memory().interceptWith(selects));
  final c = ProviderContainer(overrides: [
    syncDatabaseProvider.overrideWithValue(db),
    currentUserIdProvider.overrideWith((ref) => 'u1'),
  ]);
  addTearDown(c.dispose);
  addTearDown(db.close);
  return (c, db, selects);
}

/// Every value [collection] emits on one held-open subscription, as note ids.
List<List<String>> _record(ProviderContainer c, SmartCollection collection) {
  final seen = <List<String>>[];
  final sub = c.listen<AsyncValue<List<String>>>(collection.noteIds, (_, next) {
    final v = next.valueOrNull;
    if (v != null) seen.add(v);
  }, fireImmediately: true);
  addTearDown(sub.close);
  return seen;
}

/// Waits for [ok], polling, and fails with what was seen if it never holds.
Future<void> _until(List<List<String>> seen, bool Function(List<String>) ok,
    String what) async {
  for (var i = 0; i < 200; i++) {
    if (seen.isNotEmpty && ok(seen.last)) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('$what — never happened; saw ${seen.isEmpty ? 'nothing' : seen}');
}

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  group('the collections follow edits', () {
    test('tagging a note takes it out of Untagged', () async {
      // Tagging writes only sync_note_tags. The query has to have been told it
      // reads that table, or this write goes unnoticed.
      final (c, _) = _live();
      final notes = c.read(noteRepositoryProvider);
      await notes.createNote(id: 'n1', folderId: '', userId: 'u1', title: 'A');
      await notes.createNote(id: 'n2', folderId: '', userId: 'u1', title: 'B');

      final seen = _record(c, SmartCollection.untagged);
      await _until(seen, (ids) => ids.toSet().containsAll(['n1', 'n2']),
          'both notes listed as untagged');

      await c
          .read(noteTagRepositoryProvider)
          .addTagToNote(noteId: 'n1', tagId: 't1', userId: 'u1');

      await _until(seen, (ids) => !ids.contains('n1') && ids.contains('n2'),
          'n1 leaving Untagged once tagged');
    });

    test('a new note appears in Recently Edited', () async {
      final (c, _) = _live();
      final notes = c.read(noteRepositoryProvider);
      await notes.createNote(id: 'n1', folderId: '', userId: 'u1', title: 'Old');

      final seen = _record(c, SmartCollection.recentlyEdited);
      await _until(seen, (ids) => ids.contains('n1'), 'the first note listed');

      await notes.createNote(id: 'n2', folderId: '', userId: 'u1', title: 'New');

      await _until(seen, (ids) => ids.isNotEmpty && ids.first == 'n2',
          'the new note at the top of Recently Edited');
    });

    test('editing an old note takes it out of No Activity 30d', () async {
      final (c, db) = _live();
      final notes = c.read(noteRepositoryProvider);
      await notes.createNote(id: 'n1', folderId: '', userId: 'u1', title: 'Old');
      // Backdated before anything subscribes, so the setup is not the edit.
      final longAgo = DateTime.now()
          .subtract(const Duration(days: 60))
          .millisecondsSinceEpoch;
      await db.customUpdate(
        'UPDATE sync_notes SET updated_at = ? WHERE id = ?',
        variables: [Variable.withInt(longAgo), Variable.withString('n1')],
        updates: {db.syncNotes},
      );

      final seen = _record(c, SmartCollection.stale);
      await _until(seen, (ids) => ids.contains('n1'), 'the old note listed');

      await notes.updateNote(id: 'n1', title: 'Old, revisited');

      await _until(seen, (ids) => !ids.contains('n1'),
          'the edited note leaving No Activity 30d');
    });

    test('and stop querying once nothing is watching', () async {
      // A live query re-runs on every write to its tables. Kept alive forever,
      // all three would re-query on every save anywhere in the app; they are
      // autoDispose so they run only while the filter bar or a chosen
      // collection needs them.
      final (c, _) = _live();
      final sub = c.listen(SmartCollection.untagged.noteIds, (_, _) {});
      expect(c.exists(SmartCollection.untagged.noteIds), isTrue);

      sub.close();
      await Future<void>.delayed(Duration.zero);

      expect(c.exists(SmartCollection.untagged.noteIds), isFalse,
          reason: 'no listener, so the query should be torn down');
    });
  });

  group('the collections are cheap to keep live', () {
    test('they fetch ids, never whole rows', () async {
      // Every re-run used to carry each matching note's full body
      // (document_json) across — 30ms instead of 1ms at 2,000 notes of 4KB —
      // for consumers that read only the id and the count. Pinned on the SQL
      // the database actually runs, because a timing test would be flaky and a
      // `SELECT *` that only *reads* `id` would pass any test of the results.
      final (c, _, selects) = _watched();
      await c.read(noteRepositoryProvider)
          .createNote(id: 'n1', folderId: '', userId: 'u1', title: 'A');
      selects.sql.clear();

      for (final collection in SmartCollection.values) {
        final seen = _record(c, collection);
        await _until(seen, (_) => true, '${collection.name} answering');
      }

      final collectionQueries = selects.sql
          .where((q) => q.contains('sync_notes'))
          .toList();
      expect(collectionQueries, hasLength(SmartCollection.values.length),
          reason: 'one query per collection — or this inspected nothing');
      for (final q in collectionQueries) {
        expect(q, isNot(matches(RegExp(r'SELECT\s+(n\.)?\*'))),
            reason: 'a collection query selects whole rows: $q');
        expect(q, matches(RegExp(r'^SELECT (n\.)?id FROM')),
            reason: 'it should ask for the id alone: $q');
      }
    });

    test('a write that changes nothing in a collection is not passed on',
        () async {
      // Most writes — an autosave of a note's text — re-run every live query on
      // the table and leave the result exactly as it was: four of every five,
      // in a burst of saves. Each still re-sorted the list and rebuilt the
      // screen. Two things are asserted, because either alone proves nothing:
      // the query really did re-run, and nothing new reached the listener.
      final (c, _, selects) = _watched();
      final notes = c.read(noteRepositoryProvider);
      await notes.createNote(id: 'n1', folderId: '', userId: 'u1', title: 'A');

      final seen = _record(c, SmartCollection.untagged);
      await _until(seen, (ids) => ids.contains('n1'), 'n1 listed as untagged');
      final emitted = seen.length;
      final ran = selects.sql.where((q) => q.contains('sync_note_tags')).length;

      // Someone else's note: the table changes, this user's collection does not.
      await notes.createNote(id: 'x1', folderId: '', userId: 'u2', title: 'B');
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(selects.sql.where((q) => q.contains('sync_note_tags')).length,
          greaterThan(ran),
          reason: 'the query must have re-run, or nothing was tested');
      expect(seen.length, emitted,
          reason: 'an identical answer must not be passed on');
    });
  });

  group('a chosen collection that has not answered', () {
    // visibleNotesProvider over a collection whose stream the test controls.
    Future<(ProviderContainer, StreamController<List<String>>)> chosen()
        async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final untagged = StreamController<List<String>>();
      addTearDown(untagged.close);
      final c = ProviderContainer(overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        notesStreamProvider.overrideWith((ref) => Stream.value([
          domain.Note.create(id: 'a', title: 'Tagged'),
          domain.Note.create(id: 'b', title: 'Loose'),
        ])),
        untaggedNoteIdsProvider.overrideWith((ref) => untagged.stream),
      ]);
      addTearDown(c.dispose);
      final held = c.listen(visibleNotesProvider, (_, _) {});
      addTearDown(held.close);
      await c.read(notesStreamProvider.future);
      c.read(notesHomeUiProvider.notifier)
          .setSmartCollection(SmartCollection.untagged);
      return (c, untagged);
    }

    String model(String id) => id;

    test('is loading — not every note', () async {
      // It fell through to the unfiltered branch, so the whole notebook sat
      // under a heading that said Untagged until the query landed.
      final (c, _) = await chosen();
      final visible = c.read(visibleNotesProvider);

      expect(visible.isLoading, isTrue);
      expect(visible.hasValue, isFalse,
          reason: 'there must be no list to show yet, least of all all of it');
    });

    test('and one that failed is an error, not every note', () async {
      // The fallthrough was permanent on failure: every note, labelled Untagged,
      // for as long as the collection stayed chosen.
      final (c, untagged) = await chosen();
      untagged.addError(StateError('query failed'));
      await Future<void>.delayed(Duration.zero);

      expect(c.read(visibleNotesProvider).hasError, isTrue);
    });

    test('once it answers, the list is the collection', () async {
      final (c, untagged) = await chosen();
      untagged.add([model('b')]);
      await Future<void>.delayed(Duration.zero);

      expect(c.read(visibleNotesProvider).valueOrNull?.map((n) => n.id), ['b']);
    });

    test('and later updates swap the list without a loading flash', () async {
      // Following edits must not blank the list each time: after the first
      // answer, a re-run keeps showing data until the next one arrives.
      final (c, untagged) = await chosen();
      final states = <AsyncValue<List<domain.Note>>>[];
      final sub = c.listen(visibleNotesProvider, (_, next) => states.add(next));
      addTearDown(sub.close);

      // Real milliseconds, not a zero delay: a dependent provider recomputes on
      // Riverpod's scheduler, after the microtask that delivered the event.
      Future<void> settle() =>
          Future<void>.delayed(const Duration(milliseconds: 20));

      untagged.add([model('b')]);
      await settle();
      expect(states.last.valueOrNull?.map((n) => n.id), ['b'],
          reason: 'the first answer has to land before the second can be judged');
      states.clear();

      untagged.add([model('a'), model('b')]);
      await settle();

      expect(states, isNotEmpty);
      expect(states.where((s) => !s.hasValue), isEmpty,
          reason: 'no state without a list once the collection has answered');
      expect(states.last.valueOrNull?.map((n) => n.id).toSet(), {'a', 'b'});
    });
  });
}
