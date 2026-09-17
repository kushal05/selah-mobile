// The filter badge renders a count through string interpolation, which the
// analyzer cannot check: `'$_ui.activeFilterCount'` is valid Dart that prints
// "Instance of 'NotesHomeUiState'.activeFilterCount". A bulk rename of the
// screen's state fields introduced exactly that, and nothing caught it —
// analyze was clean and every other test still passed.
//
// This asserts the rendered text is a bare number.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:notify/core/sync/providers/sync_providers.dart';
import 'package:notify/core/theme/app_theme.dart';
import 'package:notify/l10n/l10n.dart';
import 'package:notify/features/notes/presentation/providers/database_provider.dart';
import 'package:notify/features/notes/presentation/providers/notes_home_ui_state.dart';
import 'package:notify/features/notes/presentation/screens/notes_home_screen.dart';

void main() {
  testWidgets('the filter badge shows a number, not an object', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        notesStreamProvider.overrideWith((ref) => Stream.value(const [])),
        noteFoldersStreamProvider.overrideWith(
          (ref) => Stream.value(const []),
        ),
        peopleStreamProvider.overrideWith((ref) => Stream.value(const [])),
        tagsStreamProvider.overrideWith((ref) => Stream.value(const [])),
      ],
    );
    addTearDown(container.dispose);

    // Two active filters, so the badge has something to draw.
    container.read(notesHomeUiProvider.notifier)
      ..setTagFilter({'tag-1'})
      ..setPreacherFilter('person-1');

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const NotesHomeScreen(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      find.text('2'),
      findsOneWidget,
      reason: 'the badge must render the count itself',
    );
    expect(
      find.textContaining('Instance of'),
      findsNothing,
      reason: 'an object leaked into a string interpolation',
    );
  });
}
