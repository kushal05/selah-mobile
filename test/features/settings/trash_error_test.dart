// Trash must never claim to be empty when it does not know.
//
// The screen merges eight stream providers with whenData, which fires only on
// success. Before this test existed, a provider that errored contributed
// nothing and said nothing: the category vanished, and if every source failed
// the screen rendered "Trash is empty" — telling the user their deleted items
// were gone when in fact reading them had failed. On a recovery surface that
// is the most costly possible wrong answer.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:notify/core/sync/providers/sync_providers.dart';
import 'package:notify/core/theme/app_theme.dart';
import 'package:notify/l10n/l10n.dart';
import 'package:notify/features/settings/presentation/screens/trash_screen.dart';

/// Every source the trash screen reads.
List<Override> _allTrashSources({required bool failing}) {
  Stream<List<T>> s<T>() =>
      failing ? Stream<List<T>>.error(Exception('db unavailable')) : Stream.value(<T>[]);
  return [
    trashedNotesStreamProvider.overrideWith((ref) => s()),
    trashedFoldersStreamProvider.overrideWith((ref) => s()),
    trashedPrayersStreamProvider.overrideWith((ref) => s()),
    trashedPromisesStreamProvider.overrideWith((ref) => s()),
    trashedSongsStreamProvider.overrideWith((ref) => s()),
    trashedPeopleStreamProvider.overrideWith((ref) => s()),
    trashedPreachersStreamProvider.overrideWith((ref) => s()),
    trashedTagsStreamProvider.overrideWith((ref) => s()),
  ];
}

Future<void> _pump(WidgetTester tester, {required bool failing}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        ..._allTrashSources(failing: failing),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const TrashScreen(),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets('a failing source never renders "Trash is empty"', (tester) async {
    await _pump(tester, failing: true);

    expect(find.text('Trash is empty'), findsNothing,
        reason: 'a read failure was reported to the user as an empty trash');
    expect(find.textContaining('Retry'), findsWidgets,
        reason: 'the user needs a way to try again');
  });

  testWidgets('a genuinely empty trash still says so', (tester) async {
    await _pump(tester, failing: false);
    expect(find.text('Trash is empty'), findsOneWidget);
  });
}
