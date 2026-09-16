// Bible search's empty state used to read "The Bible database has no verses.
// Please reinstall the app to restore the data." — wrong advice, since
// reinstalling is not how a Bible gets onto the device, and a dead end, since
// there was nothing on the screen to act on.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:notify/core/theme/app_theme.dart';
import 'package:notify/l10n/app_localizations.dart';
import 'package:notify/features/bible/domain/models/bible_version_info.dart';
import 'package:notify/features/bible/presentation/providers/bible_providers.dart';
import 'package:notify/features/bible/presentation/widgets/bible_download_prompt.dart';
import 'package:notify/features/bible_search/presentation/screens/bible_search_screen.dart';

void main() {
  testWidgets('with no Bible at all, search offers the download instead',
      (tester) async {
    tester.view.physicalSize = const Size(402, 874) * 3;
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        // No Bible database is open here, which is exactly what someone who
        // has never downloaded a translation has. That lands on the
        // "not available" branch, not the "open but empty" one — the two are
        // different states and only this one is what the user reported.
        bibleTranslationsProvider.overrideWithValue(const <String>[]),
        bibleVersionStatesProvider.overrideWith((ref) => Stream.value([
              const BibleVersionInfo(
                code: 'NKJV',
                name: 'New King James Version',
                downloadUrl: 'https://example.invalid/nkjv.zip',
                approximateSizeMb: 8,
                sortOrder: 0,
                isDefault: true,
                isDownloaded: false,
              ),
            ])),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const BibleSearchScreen(),
      ),
    ));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.byType(BibleDownloadPrompt), findsOneWidget);
    expect(find.textContaining('restart the app'), findsNothing);
    expect(find.textContaining('reinstall the app'), findsNothing);
    expect(find.text('New King James Version'), findsOneWidget);
  });
}
