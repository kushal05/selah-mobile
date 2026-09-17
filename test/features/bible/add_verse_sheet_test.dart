// Guards the add-a-verse sheet's controller lifetime.
//
// The obvious way to avoid leaking the sheet's three TextEditingControllers is
// to create them in the caller and dispose them in a `finally` after
// `await showModalBottomSheet(...)`. That is wrong, and wrong in a way that
// looks right: the future resolves on the *first frame of the pop animation*,
// while the TextFields are still mounted, so the next frame reads a disposed
// controller and the framework throws "A TextEditingController was used after
// being disposed".
//
// This test dismisses the sheet and pumps the pop animation frame by frame,
// which is exactly the window that bug lives in.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:notify/core/sync/providers/sync_providers.dart';
import 'package:notify/core/theme/app_theme.dart';
import 'package:notify/l10n/l10n.dart';
import 'package:notify/features/bible/presentation/providers/memory_verse_providers.dart';
import 'package:notify/features/bible/presentation/screens/memorization_screen.dart';

void main() {
  testWidgets('the add-verse sheet survives being dismissed', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          memoryVersesStreamProvider.overrideWith(
            (ref) => Stream.value(const []),
          ),
          dueMemoryVersesProvider.overrideWith((ref) async => const []),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const MemorizationScreen(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNWidgets(3));

    // Dismiss it the way the scrim or the drag handle does.
    Navigator.of(tester.element(find.byType(TextField).first)).pop();

    // Pump the pop animation frame by frame. Disposing the controllers when
    // the sheet future resolves would throw partway through this loop.
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(TextField), findsNothing);
  });
}
