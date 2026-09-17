// A freshly signed-in device is empty until the first pull lands. Nothing on
// screen used to distinguish that from "you have no data" — the offline banner
// says nothing about sync, and the degraded banner needs ten consecutive
// failures, which is over two hours at the retry cadence. So a new user whose
// first pull was slow or had failed once saw an empty app and no reason for it.
//
// This banner exists only for that window, which is what these tests pin: it
// speaks before the first pull lands, it says something different when that
// pull has failed, and it disappears permanently once data has arrived so it
// cannot become noise for an established user.

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:notify/core/database/sync_database.dart';
import 'package:notify/core/sync/engine/sync_state_machine.dart';
import 'package:notify/core/sync/providers/sync_providers.dart';
import 'package:notify/core/theme/app_theme.dart';
import 'package:notify/l10n/l10n.dart';
import 'package:notify/shared/widgets/first_sync_banner.dart';

void main() {
  late SyncDatabase db;

  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  setUp(() {
    db = SyncDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async => db.close());

  Future<void> pump(WidgetTester tester, SyncEngineState state) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          syncDatabaseProvider.overrideWithValue(db),
          syncProgressProvider.overrideWith(
            (ref) => Stream.value(
              SyncProgress(
                state: state,
                pendingOps: 0,
                totalOps: 0,
                percentage: 0,
              ),
            ),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: FirstSyncBanner()),
        ),
      ),
    );
    // hasCompletedFirstSyncProvider reads the database, and the banner
    // deliberately stays hidden until that resolves rather than flashing.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('it explains the wait while the first pull runs', (tester) async {
    await pump(tester, SyncEngineState.pulling);

    expect(
      find.textContaining('Getting your data'),
      findsOneWidget,
      reason: 'an empty app mid-first-pull must say the data is coming',
    );
  });

  testWidgets('a failed first pull says so and offers a retry', (tester) async {
    await pump(tester, SyncEngineState.error);

    expect(find.textContaining("couldn't load your data"), findsOneWidget);
    expect(
      find.text('Try again'),
      findsOneWidget,
      reason: 'the user needs a way out that is not waiting 15 minutes for the '
          'next periodic sync',
    );
  });

  testWidgets('it stays silent once the first pull has landed', (tester) async {
    await db.updateSyncState(
      const SyncStateCompanion(lastPullTimestamp: Value(1000)),
    );

    await pump(tester, SyncEngineState.error);

    expect(
      find.textContaining('Getting your data'),
      findsNothing,
      reason: 'this is a first-run explanation, not a general error bar — '
          'ongoing trouble is the degraded banner',
    );
    expect(find.textContaining("couldn't load your data"), findsNothing);
  });

  testWidgets('it defers to the offline banner when offline', (tester) async {
    await pump(tester, SyncEngineState.offline);

    expect(
      find.byType(Container),
      findsNothing,
      reason: 'two stacked bars saying overlapping things is worse than one',
    );
  });

  testWidgets('it stays silent when sync is idle', (tester) async {
    await pump(tester, SyncEngineState.idle);

    expect(find.textContaining('Getting your data'), findsNothing);
  });
}
