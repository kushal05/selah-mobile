// The bookmark button read `valueOrNull ?? false`, so "not read yet" and "not
// bookmarked" looked the same. toggleBookmark re-queries the database rather
// than trusting the button, so a tap while the read was still in flight found
// the existing row and deleted it — a tap meant to bookmark a chapter removes
// the bookmark instead.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:notify/core/theme/app_theme.dart';
import 'package:notify/l10n/app_localizations.dart';
import 'package:notify/features/bible/presentation/providers/bible_chapter_providers.dart';
import 'package:notify/features/bible/presentation/screens/bible_chapter_screen.dart';

Future<void> pumpChapter(WidgetTester tester, Stream<bool> bookmarked) async {
  tester.view.physicalSize = const Size(402, 874) * 3;
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(ProviderScope(
    overrides: [
      isChapterBookmarkedProvider.overrideWith((ref, params) => bookmarked),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const BibleChapterScreen(
        bookId: 1,
        chapter: 1,
        initialTranslation: 'NKJV',
      ),
    ),
  ));
  await tester.pump();
}

IconButton bookmarkButton(WidgetTester tester) => tester
    .widgetList<IconButton>(find.byType(IconButton))
    .firstWhere((b) => (b.tooltip ?? '').toLowerCase().contains('bookmark'));

void main() {
  testWidgets('the bookmark button is inert until the state is known',
      (tester) async {
    await pumpChapter(tester, const Stream<bool>.empty());

    expect(bookmarkButton(tester).onPressed, isNull,
        reason: 'a tap here deletes the bookmark it cannot see');
  });

  testWidgets('and once known, it works', (tester) async {
    await pumpChapter(tester, Stream.value(false));
    await tester.pump();

    expect(bookmarkButton(tester).onPressed, isNotNull);
  });
}
