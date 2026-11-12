// The chapter picker: one sheet with a search box, the two testaments, and a
// tap on a book opening its chapters in place.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:notify/core/theme/app_theme.dart';
import 'package:notify/features/bible/domain/models/bible_books.dart';
import 'package:notify/features/bible/presentation/widgets/chapter_picker_sheet.dart';
import 'package:notify/l10n/app_localizations.dart';

ChapterChoice? _picked;

Future<void> _open(
  WidgetTester tester, {
  int bookId = 43, // John
  int chapter = 3,
  Size size = const Size(402, 874),
  double textScale = 1.0,
  ThemeData? theme,
}) async {
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  _picked = null;

  await tester.pumpWidget(MaterialApp(
    theme: theme ?? AppTheme.light(),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () async => _picked = await showChapterPicker(context,
                bookId: bookId, chapter: chapter),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('opens on the current book, its chapters showing', (tester) async {
    await _open(tester);

    expect(find.text('Choose a chapter'), findsOneWidget);
    expect(find.text('John'), findsOneWidget);
    // John has 21 chapters, shown as a grid; chapter 3 is the current one.
    expect(find.bySemanticsLabel('John chapter 21'), findsOneWidget);
    expect(find.bySemanticsLabel('John chapter 22'), findsNothing);
  });

  testWidgets('opens on the testament the current book is in', (tester) async {
    await _open(tester, bookId: 1, chapter: 1); // Genesis
    expect(find.text('Genesis'), findsOneWidget);
    expect(find.text('Matthew'), findsNothing);
  });

  testWidgets('and the New Testament for a book in it', (tester) async {
    await _open(tester); // John
    expect(find.text('John'), findsOneWidget);
    expect(find.text('Genesis'), findsNothing);
  });

  testWidgets('the testament switch shows the other books', (tester) async {
    await _open(tester);
    await tester.tap(find.text('Old Testament'));
    await tester.pumpAndSettle();

    expect(find.text('Genesis'), findsOneWidget);
    expect(find.text('Matthew'), findsNothing);
  });

  testWidgets('tapping a book opens its chapters and closes the other',
      (tester) async {
    await _open(tester);
    await tester.tap(find.text('Acts'));
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('Acts chapter 28'), findsOneWidget);
    expect(find.bySemanticsLabel('John chapter 21'), findsNothing,
        reason: 'one book open at a time');

    await tester.tap(find.text('Acts'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Acts chapter 28'), findsNothing,
        reason: 'tapping again closes it');
  });

  testWidgets('picking a chapter returns the book and chapter',
      (tester) async {
    await _open(tester);
    await tester.tap(find.text('Acts'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Acts chapter 2'));
    await tester.pumpAndSettle();

    final acts = BibleBooks.books.indexWhere((b) => b.name == 'Acts') + 1;
    expect(_picked, (bookId: acts, chapter: 2));
    expect(find.byType(ChapterPickerSheet), findsNothing, reason: 'it closes');
  });

  testWidgets('closing without choosing returns nothing', (tester) async {
    await _open(tester);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(_picked, isNull);
  });

  testWidgets('typing part of a name searches both testaments',
      (tester) async {
    await _open(tester);
    await tester.enterText(find.byType(TextField), 'tim');
    await tester.pumpAndSettle();

    expect(find.text('1 Timothy'), findsOneWidget);
    expect(find.text('2 Timothy'), findsOneWidget);
    expect(find.text('Matthew'), findsNothing);
    expect(find.text('Old Testament'), findsNothing,
        reason: 'the switch is for browsing');
  });

  testWidgets('a search with no match says so', (tester) async {
    await _open(tester);
    await tester.enterText(find.byType(TextField), 'zzzz');
    await tester.pumpAndSettle();
    expect(find.text('No results for "zzzz"'), findsOneWidget);
  });

  testWidgets('typing a reference offers a jump straight to it',
      (tester) async {
    await _open(tester);
    await tester.enterText(find.byType(TextField), 'john 3:16');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Go to John 3'));
    await tester.pumpAndSettle();
    final john = BibleBooks.books.indexWhere((b) => b.name == 'John') + 1;
    expect(_picked, (bookId: john, chapter: 3));
  });

  testWidgets('pressing search on a typed reference goes to it',
      (tester) async {
    await _open(tester);
    await tester.enterText(find.byType(TextField), 'romans 8');
    await tester.pump();
    // The keyboard's search key.
    tester.widget<TextField>(find.byType(TextField)).onSubmitted!('romans 8');
    await tester.pumpAndSettle();

    final romans = BibleBooks.books.indexWhere((b) => b.name == 'Romans') + 1;
    expect(_picked, (bookId: romans, chapter: 8));
  });

  testWidgets('a chapter that does not exist is not offered', (tester) async {
    await _open(tester);
    await tester.enterText(find.byType(TextField), 'john 99');
    await tester.pumpAndSettle();
    expect(find.textContaining('Go to'), findsNothing);
  });

  for (final entry in {
    'light': AppTheme.light(),
    'dark': AppTheme.dark(),
  }.entries) {
    testWidgets('lays out on a narrow phone at 200% text, ${entry.key}',
        (tester) async {
      await _open(tester,
          theme: entry.value, size: const Size(320, 640), textScale: 2.0);
      expect(tester.takeException(), isNull);
      expect(find.text('John'), findsOneWidget);
    });
  }
}
