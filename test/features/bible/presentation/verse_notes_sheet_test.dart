// The verse sheet's "Your notes": below all the options, each note cut to two
// lines with an underlined "See more", notes separated by a line, and "Add
// note" actually saving a note that then shows up.

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
import 'package:notify/features/bible/presentation/widgets/highlight_bottom_sheet.dart';
import 'package:notify/l10n/app_localizations.dart';

const _book = 43;
const _chapter = 3;
const _verse = 16;

final _long = 'This verse is the heart of the gospel. ' * 12;

void main() {
  late SyncDatabase db;
  late ProviderContainer container;
  final saved = <HighlightColor>[];

  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  setUp(() {
    saved.clear();
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
        () => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump(const Duration(milliseconds: 50));
  }

  Future<void> addNote(WidgetTester tester, String text) async {
    await tester.runAsync(() => container
        .read(bibleVerseNoteRepositoryProvider)
        .addNote(bookId: _book, chapter: _chapter, verse: _verse, content: text));
  }

  Future<void> pumpSheet(
    WidgetTester tester, {
    BibleHighlightEntity? existing,
  }) async {
    // Wider than a phone: the test font (Ahem) is far wider than a real one,
    // and the editing row (Remove, Add note, Update) would overflow in it.
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
          body: HighlightBottomSheet(
            reference: 'John 3:16',
            verseText: 'For God so loved the world',
            bookId: _book,
            chapter: _chapter,
            verse: _verse,
            existingHighlight: existing,
            onSave: saved.add,
            onSaveToNotes: (_, _) {},
            onSaveToPromises: (_, _) {},
          ),
        ),
      ),
    ));
    await settle(tester);
  }

  testWidgets('no notes, no "Your notes" section', (tester) async {
    await pumpSheet(tester);
    expect(find.text('Your notes'), findsNothing);
  });

  testWidgets('notes show below all the options, newest first', (tester) async {
    await addNote(tester, 'older note');
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)));
    await addNote(tester, 'newer note');
    await pumpSheet(tester);

    expect(find.text('Your notes'), findsOneWidget);
    final heading = tester.getTopLeft(find.text('Your notes')).dy;
    expect(heading, greaterThan(tester.getBottomLeft(find.text('Highlight')).dy),
        reason: 'below the Highlight button');
    expect(heading, greaterThan(tester.getBottomLeft(find.text('Add note')).dy));
    expect(heading,
        greaterThan(tester.getBottomLeft(find.text('Add to notes')).dy));

    expect(tester.getTopLeft(find.text('newer note')).dy,
        lessThan(tester.getTopLeft(find.text('older note')).dy));
    // A line between the two notes (plus the one above the heading).
    expect(find.byType(Divider), findsNWidgets(2));
  });

  testWidgets('a short note has no "See more"', (tester) async {
    await addNote(tester, 'short');
    await pumpSheet(tester);
    expect(find.text('See more'), findsNothing);
  });

  testWidgets('a long note is two lines with an underlined "See more" that '
      'opens it in full', (tester) async {
    await addNote(tester, _long);
    await pumpSheet(tester);

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
    await pumpSheet(tester);
    expect(find.text('Your notes'), findsNothing);

    await tester.tap(find.text('Add note'));
    await tester.pump();

    // Nothing to save yet.
    expect(find.widgetWithText(TextButton, 'Save note'), findsOneWidget);
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
    expect(rows.single.verseStart, _verse);
  });

  testWidgets('Highlight saves a colour and does not create a note',
      (tester) async {
    await pumpSheet(tester);
    await tester.tap(find.text('Highlight'));
    await tester.pump();

    expect(saved, [HighlightColor.yellow]);
    final rows = await tester.runAsync(() => db.select(db.bibleVerseNotes).get());
    expect(rows, isEmpty);
  });

  testWidgets("a note typed into a highlight before this stays visible",
      (tester) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await pumpSheet(
      tester,
      existing: BibleHighlightEntity(
        id: 'h1',
        bookId: _book,
        chapter: _chapter,
        verseStart: _verse,
        verseEnd: _verse,
        color: HighlightColor.green,
        note: 'written long ago',
        createdAt: now,
        updatedAt: now,
      ),
    );

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
      await pumpSheet(tester);

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
      await pumpSheet(tester);

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
      await pumpSheet(tester);

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
      await addNote(tester, 'staying');
      await pumpSheet(tester);

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
      await pumpSheet(tester);

      await openMenu(tester);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await settle(tester);
      await settle(tester);

      expect(find.text('Your notes'), findsNothing);
    });

    testWidgets("a note typed into a highlight can be edited and deleted too",
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
      await pumpSheet(tester, existing: h);
      expect(find.text('written long ago'), findsOneWidget);

      await openMenu(tester);
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'updated long ago');
      await tester.pump();
      await tester.tap(find.widgetWithText(TextButton, 'Save'));
      await settle(tester);
      await settle(tester);

      expect(find.text('updated long ago'), findsOneWidget);
      var rows =
          await tester.runAsync(() => db.select(db.bibleHighlights).get());
      expect(rows!.single.note, 'updated long ago');
      expect(rows.single.deleted, 0, reason: 'still highlighted');

      await openMenu(tester);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await settle(tester);
      await settle(tester);

      expect(find.text('Your notes'), findsNothing);
      rows = await tester.runAsync(() => db.select(db.bibleHighlights).get());
      expect(rows!.single.note, isEmpty);
      expect(rows.single.deleted, 0, reason: 'the highlight itself stays');
    });
  });
}
