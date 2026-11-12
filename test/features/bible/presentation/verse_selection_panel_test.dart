// The selection panel's "Your notes": below all the options, each note cut to
// two lines with an underlined "See more", notes separated by a line, each
// labelled with the verses it was written on; "Add note" saving a note on the
// whole selection, and only when the selected verses are next to each other.

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:notify/core/database/sync_database.dart';
import 'package:notify/core/sync/providers/sync_providers.dart';
import 'package:notify/core/theme/app_theme.dart';
import 'package:notify/features/bible/domain/models/bible_highlight_entity.dart';
import 'package:notify/features/bible/presentation/providers/bible_chapter_providers.dart';
import 'package:notify/features/bible/presentation/widgets/verse_selection_panel.dart';
import 'package:notify/l10n/app_localizations.dart';

const _book = 43;
const _chapter = 3;
const _verse = 16;

final _long = 'This verse is the heart of the gospel. ' * 12;

BibleHighlightEntity _highlight({String note = ''}) {
  final now = DateTime.now().millisecondsSinceEpoch;
  return BibleHighlightEntity(
    id: 'h1',
    bookId: _book,
    chapter: _chapter,
    verseStart: _verse,
    verseEnd: _verse,
    color: HighlightColor.green,
    note: note,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  late SyncDatabase db;
  late ProviderContainer container;
  final colors = <HighlightColor>[];
  var removed = 0;

  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  setUp(() {
    colors.clear();
    removed = 0;
    db = SyncDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(overrides: [
      syncDatabaseProvider.overrideWithValue(db),
      currentUserIdProvider.overrideWith((ref) => 'user-1'),
      deviceIdProvider.overrideWith((ref) => 'device-1'),
    ]);
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 150)));
    await tester.pump(const Duration(milliseconds: 50));
  }

  Future<void> addNote(WidgetTester tester, String text,
      {int verse = _verse, int? verseEnd}) async {
    await tester.runAsync(() => container
        .read(bibleVerseNoteRepositoryProvider)
        .addNote(
            bookId: _book,
            chapter: _chapter,
            verse: verse,
            verseEnd: verseEnd,
            content: text));
  }

  Future<void> pumpPanel(
    WidgetTester tester, {
    BibleHighlightEntity? existing,
    Set<int> selected = const {_verse},
  }) async {
    // Wider than a phone: the test font (Ahem) is far wider than a real one.
    tester.view.physicalSize = const Size(600, 874) * 3;
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: VerseSelectionPanel(
              reference: 'John 3:16',
              bookId: _book,
              chapter: _chapter,
              selected: selected,
              highlights: [if (existing != null) existing],
              onColor: colors.add,
              onRemoveHighlight: () => removed++,
              onClose: () {},
              onAddToNotes: () {},
              onSaveAsPromise: () {},
            ),
          ),
        ),
      ),
    ));
    await settle(tester);
  }

  testWidgets('no notes, no "Your notes" section', (tester) async {
    await pumpPanel(tester);
    expect(find.text('Your notes'), findsNothing);
  });

  testWidgets('notes show below all the options, newest first', (tester) async {
    await addNote(tester, 'older note');
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)));
    await addNote(tester, 'newer note');
    await pumpPanel(tester);

    expect(find.text('Your notes'), findsOneWidget);
    final heading = tester.getTopLeft(find.text('Your notes')).dy;
    expect(heading, greaterThan(tester.getBottomLeft(find.text('Add note')).dy));
    expect(heading,
        greaterThan(tester.getBottomLeft(find.text('Add to notes')).dy));

    expect(tester.getTopLeft(find.text('newer note')).dy,
        lessThan(tester.getTopLeft(find.text('older note')).dy));
    // A line between the two notes (plus the one above the heading).
    expect(find.byType(Divider), findsNWidgets(2));
    expect(find.text('Verse 16'), findsNWidgets(2),
        reason: 'each note says which verse it is on');
  });

  testWidgets('a short note has no "See more"', (tester) async {
    await addNote(tester, 'short');
    await pumpPanel(tester);
    expect(find.text('See more'), findsNothing);
  });

  testWidgets(
      'a long note is two lines with an underlined "See more" that opens it '
      'in full', (tester) async {
    await addNote(tester, _long);
    await pumpPanel(tester);

    Text noteText() => tester.widget<Text>(find.text(_long));
    expect(noteText().maxLines, 2);
    expect(noteText().overflow, TextOverflow.ellipsis);

    final seeMore = find.text('See more');
    expect(seeMore, findsOneWidget);
    expect(tester.widget<Text>(seeMore).style?.decoration,
        TextDecoration.underline);

    await tester.tap(seeMore);
    await tester.pump();

    expect(noteText().maxLines, isNull, reason: 'now the whole note');
    expect(find.text('See more'), findsNothing);
  });

  testWidgets('Add note saves a note that appears under "Your notes"',
      (tester) async {
    await pumpPanel(tester);
    expect(find.text('Your notes'), findsNothing);

    await tester.tap(find.text('Add note'));
    await tester.pump();

    // Nothing to save yet.
    expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Save note'))
            .onPressed,
        isNull);

    await tester.enterText(find.byType(TextField), 'my thought on this verse');
    await tester.pump();
    await tester.tap(find.widgetWithText(TextButton, 'Save note'));
    await settle(tester);
    await settle(tester);

    expect(find.text('Your notes'), findsOneWidget);
    expect(find.text('my thought on this verse'), findsOneWidget);
    expect(find.byType(TextField), findsNothing, reason: 'the field closes');

    final rows = await tester.runAsync(() => db.select(db.bibleVerseNotes).get());
    expect(rows!.single.content, 'my thought on this verse');
    expect(rows.single.bookId, _book);
    expect([rows.single.verseStart, rows.single.verseEnd], [_verse, _verse]);
  });

  testWidgets('tapping a colour applies it at once and creates no note',
      (tester) async {
    await pumpPanel(tester);
    await tester.tap(find.bySemanticsLabel('Pink highlight'));
    await tester.pump();

    expect(colors, [HighlightColor.pink]);
    final rows = await tester.runAsync(() => db.select(db.bibleVerseNotes).get());
    expect(rows, isEmpty);
  });

  testWidgets('"Remove highlight" is offered only on a highlighted verse',
      (tester) async {
    await pumpPanel(tester);
    expect(find.text('Remove highlight'), findsNothing);
  });

  testWidgets('"Remove highlight" removes it', (tester) async {
    await pumpPanel(tester, existing: _highlight());
    await tester.tap(find.text('Remove highlight'));
    expect(removed, 1);
  });

  group('several verses', () {
    testWidgets('a note is written on the whole selection', (tester) async {
      await pumpPanel(tester, selected: {15, 16, 17});
      await tester.tap(find.text('Add note'));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'about all three');
      await tester.pump();
      await tester.tap(find.widgetWithText(TextButton, 'Save note'));
      await settle(tester);
      await settle(tester);

      final rows =
          await tester.runAsync(() => db.select(db.bibleVerseNotes).get());
      expect([rows!.single.verseStart, rows.single.verseEnd], [15, 17]);
      expect(find.text('Verses 15–17'), findsOneWidget,
          reason: 'the note says it is for a group');
    });

    testWidgets('verses that are not next to each other cannot take a note',
        (tester) async {
      await pumpPanel(tester, selected: {14, 16});

      expect(find.text('Select neighbouring verses to add a note'),
          findsOneWidget);
      final add = tester.widget<InkWell>(find.ancestor(
          of: find.text('Add note'), matching: find.byType(InkWell)));
      expect(add.onTap, isNull);
      // The other actions still work on the selection.
      expect(find.text('Save as promise'), findsOneWidget);
    });

    testWidgets('a group note shows on each of its verses, labelled',
        (tester) async {
      await addNote(tester, 'the whole passage', verse: 14, verseEnd: 17);
      await pumpPanel(tester, selected: {16});

      expect(find.text('the whole passage'), findsOneWidget);
      expect(find.text('Verses 14–17'), findsOneWidget);
    });

    testWidgets('a note on another verse is not shown', (tester) async {
      await addNote(tester, 'on sixteen');
      await pumpPanel(tester, selected: {20});
      expect(find.text('on sixteen'), findsNothing);
      expect(find.text('Your notes'), findsNothing);
    });

    testWidgets('selecting two verses shows the notes of both', (tester) async {
      await addNote(tester, 'on sixteen');
      await addNote(tester, 'on twenty', verse: 20);
      await pumpPanel(tester, selected: {16, 20});
      expect(find.text('on sixteen'), findsOneWidget);
      expect(find.text('on twenty'), findsOneWidget);
    });
  });

  testWidgets('a note typed into a highlight before this stays visible',
      (tester) async {
    await pumpPanel(tester, existing: _highlight(note: 'written long ago'));

    expect(find.text('Your notes'), findsOneWidget);
    expect(find.text('written long ago'), findsOneWidget);
  });

  group('editing and deleting a note', () {
    Future<void> openMenu(WidgetTester tester) async {
      await tester.tap(find.byTooltip('More options').first);
      await tester.pumpAndSettle();
    }

    testWidgets('Edit changes the note in place and keeps it in the list',
        (tester) async {
      await addNote(tester, 'first draft');
      await pumpPanel(tester);

      await openMenu(tester);
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();

      // The field starts with the note's own text.
      final field = find.byType(TextField);
      expect(tester.widget<TextField>(field).controller!.text, 'first draft');

      await tester.enterText(field, 'second draft');
      await tester.pump();
      await tester.tap(find.widgetWithText(TextButton, 'Save'));
      await settle(tester);
      await settle(tester);

      expect(find.text('second draft'), findsOneWidget);
      expect(find.text('first draft'), findsNothing);
      expect(find.byType(TextField), findsNothing, reason: 'back to reading');

      final rows =
          await tester.runAsync(() => db.select(db.bibleVerseNotes).get());
      expect(rows!.single.content, 'second draft');
      expect(rows.single.version, 2);
      final ops = await tester.runAsync(() => db.select(db.oplog).get());
      expect(ops!.map((o) => o.operation), ['INSERT', 'UPDATE']);
    });

    testWidgets('Cancel leaves the note as it was', (tester) async {
      await addNote(tester, 'keep me');
      await pumpPanel(tester);

      await openMenu(tester);
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'changed my mind');
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('keep me'), findsOneWidget);
      final rows =
          await tester.runAsync(() => db.select(db.bibleVerseNotes).get());
      expect(rows!.single.content, 'keep me');
      expect(rows.single.version, 1);
    });

    testWidgets('a note cannot be saved empty', (tester) async {
      await addNote(tester, 'something');
      await pumpPanel(tester);

      await openMenu(tester);
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '   ');
      await tester.pump();

      expect(
          tester
              .widget<TextButton>(find.widgetWithText(TextButton, 'Save'))
              .onPressed,
          isNull);
    });

    testWidgets('Delete asks first, then removes the note', (tester) async {
      await addNote(tester, 'going away');
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await addNote(tester, 'staying');
      await pumpPanel(tester);

      await openMenu(tester); // newest first: this is "staying"
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(find.text('Delete this note?'), findsOneWidget);

      // Cancelling keeps it.
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('staying'), findsOneWidget);

      await openMenu(tester);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await settle(tester);
      await settle(tester);

      expect(find.text('staying'), findsNothing);
      expect(find.text('going away'), findsOneWidget);

      final rows =
          await tester.runAsync(() => db.select(db.bibleVerseNotes).get());
      expect(rows!.where((r) => r.deleted == 1).single.content, 'staying');
      final ops = await tester.runAsync(() => db.select(db.oplog).get());
      expect(ops!.map((o) => o.operation).toList().last, 'DELETE');
    });

    testWidgets('deleting the last note removes the whole section',
        (tester) async {
      await addNote(tester, 'only one');
      await pumpPanel(tester);

      await openMenu(tester);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await settle(tester);
      await settle(tester);

      expect(find.text('Your notes'), findsNothing);
    });

    testWidgets('a note typed into a highlight can be edited and deleted too',
        (tester) async {
      final h = await tester.runAsync(() => container
          .read(bibleHighlightRepositoryProvider)
          .createHighlight(
            bookId: _book,
            chapter: _chapter,
            verseStart: _verse,
            verseEnd: _verse,
            color: HighlightColor.green,
            note: 'written long ago',
          ));
      await pumpPanel(tester, existing: h);
      expect(find.text('written long ago'), findsOneWidget);

      await openMenu(tester);
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'updated long ago');
      await tester.pump();
      await tester.tap(find.widgetWithText(TextButton, 'Save'));
      await settle(tester);
      await settle(tester);

      var rows =
          await tester.runAsync(() => db.select(db.bibleHighlights).get());
      expect(rows!.single.note, 'updated long ago');
      expect(rows.single.deleted, 0, reason: 'still highlighted');
    });
  });

  testWidgets('never grows taller than the room it has (keyboard up)',
      (tester) async {
    tester.view.physicalSize = const Size(600, 874) * 3;
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    for (var i = 0; i < 6; i++) {
      await addNote(tester, 'a note number $i that takes up some room');
    }
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SizedBox(
            height: 300, // what is left above the keyboard
            child: Align(
              alignment: Alignment.bottomCenter,
              child: VerseSelectionPanel(
                reference: 'John 3:16',
                bookId: _book,
                chapter: _chapter,
                selected: const {_verse},
                highlights: const [],
                onColor: (_) {},
                onRemoveHighlight: () {},
                onClose: () {},
                onAddToNotes: () {},
                onSaveAsPromise: () {},
              ),
            ),
          ),
        ),
      ),
    ));
    await settle(tester);

    expect(tester.getSize(find.byType(VerseSelectionPanel)).height,
        lessThanOrEqualTo(300 * 0.9 + 0.5));
    expect(tester.takeException(), isNull);
  });
}
