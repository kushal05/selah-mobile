// Leaving the editor with the system back gesture must not discard what was
// typed.
//
// The editor saves on a debounce, and `noteEditorProvider` is autoDispose: when
// the route goes away the notifier is disposed, and its dispose() cancels the
// pending timer rather than firing it. The only flush on the way out was
// `_handleBack`, wired to the app bar's back arrow — so the Android system back
// button, the predictive-back gesture and the iOS edge swipe all popped the
// route with the timer still pending and the edit unwritten.
//
// The window is the debounce, which is now a second rather than 300ms, so this
// is worth holding in place with a test.
//
// What this pins is the interception: remove it and the assertions below fail.
// It does not pin the `await` in `_leaveEditor` — dropping it still passes,
// because the route transition gives the write time to finish before disposal.
// The await is there because `_save` returns at its first `_disposed` check, so
// a flush racing teardown could persist the body and skip `setTagsForNote`,
// leaving a note that looks saved with a tag edit silently gone. That race is
// not reproducible here, so treat the await as deliberate insurance rather than
// as something this test defends.

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:notify/core/database/sync_database.dart';
import 'package:notify/l10n/app_localizations.dart';
import 'package:notify/core/sync/providers/sync_providers.dart';
import 'package:notify/features/notes/presentation/providers/note_editor_provider.dart';
import 'package:notify/features/notes/presentation/screens/note_editor_screen.dart';

const _userId = 'test-user';

void main() {
  late SyncDatabase db;
  late ProviderContainer container;

  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

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

  testWidgets('the system back button flushes the pending save', (tester) async {
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: NoteEditorScreen(),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final editor = container.read(noteEditorProvider(null).notifier);
    editor.updateTitle('Typed then swiped away');
    editor.updateBlockContent(
      editor.state.document.blocks.first.id,
      'the body I would have lost',
    );
    // A tag as well as text, because the two halves of a save can be lost
    // separately: `_save` writes the note body, then resolves tags, then calls
    // setTagsForNote, checking `_disposed` between each. A flush that races
    // teardown can therefore persist the words and drop the tag — the quieter
    // of the two losses, since the note still looks saved.
    final tag = await container
        .read(tagRepositoryProvider)
        .createTag(userId: _userId, name: 'swiped');
    editor.setTags([tag.id]);
    expect(editor.state.isDirty, isTrue, reason: 'precondition: a save is due');

    // The system back button — not the app bar arrow, which was the only path
    // that used to flush. Nothing advances the clock past the debounce, so the
    // only way the text reaches the database is an explicit flush on the way
    // out.
    await tester.binding.handlePopRoute();
    // Bounded pumping rather than pumpAndSettle, because the focused field's
    // cursor blinks forever and nothing ever settles.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    // The save has to be allowed to finish on real async: sqlite's own work
    // does not complete on pumped fake time alone, and without this the note
    // body lands while the tag write is still in flight — which looks exactly
    // like the bug this test is about and is not.
    //
    // It does not weaken the timing argument. runAsync advances real time, not
    // the fake clock the debounce is scheduled on, and only 200ms of fake time
    // has been pumped against a one-second debounce. The timer cannot be what
    // wrote any of this.
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pump();

    final rows = await db.select(db.syncNotes).get();
    expect(rows, hasLength(1), reason: 'the note should have been written');
    expect(rows.single.title, 'Typed then swiped away');

    final junction = await db.select(db.syncNoteTags).get();
    expect(junction.map((r) => r.tagId), contains(tag.id),
        reason: 'the save must run to completion, tags included');

    // Assertions first, cleanup after: the save reschedules the debounce, and
    // that timer has to be drained or the binding fails the test for leaking
    // it. Draining before asserting would let the timer, rather than the
    // flush, be what wrote the note.
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('autosave waits about a second, and no longer', (tester) async {
    // The debounce was 300ms and every keystroke re-delivered the whole notes
    // list to every mounted tab. A second was chosen deliberately as the
    // trade against how much typing a hard kill can cost. Nothing recorded
    // that choice: mutation testing put it back to 300ms and all 712 tests
    // passed, so the decision could be undone without a word.
    //
    // Both bounds are asserted. Shortening it fails the first expectation,
    // lengthening it fails the second.
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: NoteEditorScreen(),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final editor = container.read(noteEditorProvider(null).notifier);
    editor.updateTitle('Mid-debounce');

    // 900ms of the debounce gone, plus a real-async window so that a save
    // which *had* fired would have reached sqlite by now.
    await tester.pump(const Duration(milliseconds: 900));
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    expect(await db.select(db.syncNotes).get(), isEmpty,
        reason: 'nothing should be written before the debounce elapses');

    await tester.pump(const Duration(milliseconds: 300));
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pump();
    expect(await db.select(db.syncNotes).get(), hasLength(1),
        reason: 'the debounced save must have fired by 1.2s');

    await tester.pump(const Duration(seconds: 2));
  });
}
