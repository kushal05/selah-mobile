// With no Bible installed there is nothing behind the picker's three tabs.
// It used to open on the book grid regardless: you could choose a book, a
// chapter and a verse, and only at the last step find an empty panel and no
// way to insert anything — three steps of work, then a dead end.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:notify/core/theme/app_theme.dart';
import 'package:notify/l10n/app_localizations.dart';
import 'package:notify/features/bible/domain/models/bible_version_info.dart';
import 'package:notify/features/bible/presentation/providers/bible_providers.dart';
import 'package:notify/features/bible/presentation/widgets/bible_download_prompt.dart';
import 'package:notify/features/notes/presentation/widgets/editor/bible_reference_picker.dart';

BibleVersionInfo _nkjv({required bool isDownloaded}) => BibleVersionInfo(
      code: 'NKJV',
      name: 'New King James Version',
      downloadUrl: 'https://example.invalid/nkjv.zip',
      approximateSizeMb: 8,
      sortOrder: 0,
      isDefault: true,
      isDownloaded: isDownloaded,
    );

Future<void> openPicker(
  WidgetTester tester, {
  required List<String> installed,
  double width = 402,
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = Size(width, 874) * 3;
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(ProviderScope(
    overrides: [
      bibleTranslationsProvider.overrideWithValue(installed),
      bibleVersionStatesProvider.overrideWith((ref) => Stream.value([
            _nkjv(isDownloaded: installed.contains('NKJV')),
          ])),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      builder: (context, child) => MediaQuery.withClampedTextScaling(
        minScaleFactor: textScale,
        maxScaleFactor: textScale,
        child: child!,
      ),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (c) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => BibleReferencePicker.show(c),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('with no Bible installed, the first step offers the download',
      (tester) async {
    await openPicker(tester, installed: []);

    expect(find.byType(BibleDownloadPrompt), findsOneWidget);
    expect(find.text('New King James Version'), findsOneWidget);
  });

  testWidgets('and does not let you start choosing a reference',
      (tester) async {
    await openPicker(tester, installed: []);

    // The three tabs are the walk to the dead end. None of them is offered.
    for (final tab in ['BOOK', 'CHAPTER', 'VERSE']) {
      expect(find.text(tab), findsNothing, reason: '$tab tab still offered');
    }
    // Nor the book grid behind them.
    expect(find.text('Gen'), findsNothing);
    expect(find.text('Old Testament'), findsNothing);
  });

  testWidgets('with a Bible installed, it opens on the books as before',
      (tester) async {
    await openPicker(tester, installed: ['NKJV']);

    expect(find.byType(BibleDownloadPrompt), findsNothing);
    expect(find.text('BOOK'), findsOneWidget);
    expect(find.text('Gen'), findsOneWidget);
  });

  // The prompt renders in whatever room the dialog has left, which on a small
  // phone at a large text size is not much. An error state that overflows is
  // a second error on top of the first.
  for (final scale in [1.0, 2.0]) {
    testWidgets('the download prompt fits a 320pt screen at ${scale}x text',
        (tester) async {
      await openPicker(tester,
          installed: [], width: 320, textScale: scale);
      expect(tester.takeException(), isNull);
      expect(find.byType(BibleDownloadPrompt), findsOneWidget);
    });
  }

  testWidgets('book-only mode still lists books with no Bible installed',
      (tester) async {
    // The book list is a static registry, not a database read, and its one
    // caller is the Bible search filter — a screen that already says the
    // Bible is missing. Prompting there would say it twice.
    tester.view.physicalSize = const Size(402, 874) * 3;
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        bibleTranslationsProvider.overrideWithValue(const <String>[]),
        bibleVersionStatesProvider
            .overrideWith((ref) => Stream.value([_nkjv(isDownloaded: false)])),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (c) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => BibleReferencePicker.showBookPicker(c),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.byType(BibleDownloadPrompt), findsNothing);
    expect(find.text('Gen'), findsOneWidget);
    expect(find.text('Old Testament'), findsOneWidget);
  });

  testWidgets('a finished download turns the open picker into the book grid',
      (tester) async {
    // The point of downloading here rather than in Settings: the dialog stays
    // open and the task continues. Nothing reopens the picker, so if this
    // swap did not happen the user would be left staring at the prompt with a
    // Bible already installed.
    final installed = StateProvider<List<String>>((ref) => const []);

    tester.view.physicalSize = const Size(402, 874) * 3;
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    late WidgetRef widgetRef;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        bibleTranslationsProvider
            .overrideWith((ref) => ref.watch(installed)),
        bibleVersionStatesProvider.overrideWith((ref) => Stream.value(
            [_nkjv(isDownloaded: ref.watch(installed).isNotEmpty)])),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Consumer(builder: (c, ref, _) {
          widgetRef = ref;
          return Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => BibleReferencePicker.show(c),
                child: const Text('open'),
              ),
            ),
          );
        }),
      ),
    ));
    await tester.tap(find.text('open'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(BibleDownloadPrompt), findsOneWidget);
    expect(find.text('Gen'), findsNothing);

    // What a completed download amounts to: the translation is now installed.
    widgetRef.read(installed.notifier).state = const ['NKJV'];
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.byType(BibleDownloadPrompt), findsNothing);
    expect(find.text('BOOK'), findsOneWidget);
    expect(find.text('Gen'), findsOneWidget,
        reason: 'the picker should carry on where it stopped');
  });
}
