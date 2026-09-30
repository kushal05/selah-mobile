// What global search says when it could not read everything.
//
// The five collections are queried in parallel and each failure was caught and
// turned into an empty list, so a query that never ran was indistinguishable
// from one that found nothing — and the screen reported the second: "No results
// found", over content it had not looked at.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:notify/core/sync/models/person_model.dart';
import 'package:notify/core/theme/app_theme.dart';
import 'package:notify/features/search/presentation/providers/global_search_provider.dart';
import 'package:notify/features/search/presentation/screens/global_search_screen.dart';
import 'package:notify/l10n/l10n.dart';

/// A notifier parked in a fixed state. The real one needs five repositories;
/// what is under test here is what the screen makes of the state, not how the
/// state was reached.
class _FixedSearch extends GlobalSearchNotifier {
  _FixedSearch(super.ref, GlobalSearchState initial) {
    state = initial;
  }
}

PersonModel _person(String name) => PersonModel(
      id: 'p-$name',
      userId: 'u1',
      name: name,
      relation: 'friend',
      notes: '',
      updatedAt: 0,
      version: 1,
      deleted: 0,
      createdAt: 0,
    );

Future<void> _pump(WidgetTester tester, GlobalSearchState state) async {
  tester.view.physicalSize = const Size(840, 1800);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        globalSearchProvider.overrideWith((ref) => _FixedSearch(ref, state)),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const GlobalSearchScreen(),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  const searched = GlobalSearchState(hasSearched: true);

  test('the two enums over the same five collections stay in step', () {
    // SearchArea lives in the provider so it need not import the screen;
    // SearchEntityType lives in the screen and drives the filter pills. Two
    // names for one set of collections means adding a sixth can update one and
    // not the other — and the half that gets missed is the reporting half, so
    // the new collection would fail silently, which is the bug this whole file
    // exists about.
    expect(SearchArea.values.length, SearchEntityType.values.length);
    expect(
      SearchArea.values.map((a) => a.name).toSet(),
      SearchEntityType.values.map((t) => t.name).toSet(),
    );
  });

  testWidgets('nothing found is reported as nothing found', (tester) async {
    await _pump(tester, searched);

    expect(find.text('No results found'), findsOneWidget);
    expect(find.text("Couldn't search your content. Try again."), findsNothing);
  });

  testWidgets('nothing searched at all is not reported as nothing found', (
    tester,
  ) async {
    await _pump(
      tester,
      GlobalSearchState(
        hasSearched: true,
        failedAreas: SearchArea.values.toSet(),
      ),
    );

    expect(find.text('No results found'), findsNothing);
    expect(find.text("Couldn't search your content. Try again."),
        findsOneWidget);
    // And a way out of it, since the failure may not repeat.
    expect(find.widgetWithText(TextButton, 'Try again'), findsOneWidget);
  });

  testWidgets('one collection failing while the rest found nothing says both', (
    tester,
  ) async {
    // The search did run and did find nothing, so "No results found" is the
    // true headline; what it could not reach belongs beside it, not instead
    // of it. Claiming the whole search failed would send the user looking for
    // a connection problem they do not have.
    await _pump(
      tester,
      const GlobalSearchState(
        hasSearched: true,
        failedAreas: {SearchArea.notes},
      ),
    );

    expect(find.text('No results found'), findsOneWidget);
    expect(find.text("Couldn't search your content. Try again."), findsNothing);
    expect(
      find.text("Couldn't search Notes, so results may be incomplete. "
          'Try again.'),
      findsOneWidget,
    );
  });

  testWidgets('results that are missing a collection say which', (
    tester,
  ) async {
    await _pump(
      tester,
      GlobalSearchState(
        hasSearched: true,
        people: [_person('Ruth')],
        failedAreas: const {SearchArea.notes},
      ),
    );

    expect(
      find.text("Couldn't search Notes, so results may be incomplete. "
          'Try again.'),
      findsOneWidget,
    );
    // The results it did get are still shown — the notice sits above them.
    expect(find.text('Ruth'), findsOneWidget);
  });

  testWidgets('two failed collections read as a list', (tester) async {
    await _pump(
      tester,
      GlobalSearchState(
        hasSearched: true,
        people: [_person('Ruth')],
        failedAreas: const {SearchArea.songs, SearchArea.notes},
      ),
    );

    // Declaration order of the enum, not insertion order of the set, so the
    // sentence reads the same every time.
    expect(
      find.text("Couldn't search Notes and Songs, so results may be "
          'incomplete. Try again.'),
      findsOneWidget,
    );
  });

  testWidgets('three failed collections take a comma', (tester) async {
    await _pump(
      tester,
      GlobalSearchState(
        hasSearched: true,
        people: [_person('Ruth')],
        failedAreas: const {
          SearchArea.songs,
          SearchArea.notes,
          SearchArea.prayers,
        },
      ),
    );

    expect(
      find.text("Couldn't search Notes, Prayers and Songs, so results may be "
          'incomplete. Try again.'),
      findsOneWidget,
    );
  });

  testWidgets('a complete search shows no notice', (tester) async {
    await _pump(
      tester,
      GlobalSearchState(hasSearched: true, people: [_person('Ruth')]),
    );

    expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
    expect(find.text('Ruth'), findsOneWidget);
  });
}
