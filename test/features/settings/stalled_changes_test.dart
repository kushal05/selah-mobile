// Sync sets a change aside rather than dropping it when it cannot be moved —
// an outbound operation the server keeps rejecting, or an inbound one this
// device cannot apply. Neither is a crash and neither shows up anywhere else,
// so this card is the only thing standing between "set aside with a reason"
// and "silently gone" from the user's point of view.
//
// It has to do three things: stay invisible when there is nothing wrong, show
// both directions when there is, and say why.

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:notify/core/database/sync_database.dart';
import 'package:notify/core/sync/engine/sync_state_machine.dart';
import 'package:notify/core/sync/providers/sync_providers.dart';
import 'package:notify/core/theme/app_theme.dart';
import 'package:notify/l10n/l10n.dart';
import 'package:notify/features/settings/presentation/screens/sync_status_screen.dart';

void main() {
  late SyncDatabase db;

  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  setUp(() {
    db = SyncDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async => db.close());

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(840, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          syncDatabaseProvider.overrideWithValue(db),
          // The screen's other cards reach for the live sync service, which
          // would build a real API client. Only the stalled-changes card is
          // under test here.
          syncProgressProvider.overrideWith(
            (ref) => const Stream<SyncProgress>.empty(),
          ),
          pendingOpsCountProvider.overrideWith((ref) async => 0),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const SyncStatusScreen(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('nothing is shown when nothing is stalled', (tester) async {
    await pump(tester);

    expect(
      find.text('Changes needing attention'),
      findsNothing,
      reason: 'it must be a signal, not permanent furniture',
    );
  });

  testWidgets('an outbound rejection is shown with its reason', (tester) async {
    await db.into(db.oplog).insert(
      OplogCompanion.insert(
        opId: 'op-1',
        entityType: 'note',
        entityId: 'note-1',
        operation: 'UPDATE',
        payloadJson: '{}',
        timestamp: 1,
        deviceId: 'd1',
        entityVersion: 1,
        failedAt: const Value(1000),
        failedReason: const Value('VALIDATION_ERROR: rejected 5 times'),
      ),
    );

    await pump(tester);

    expect(find.text('Changes needing attention'), findsOneWidget);
    expect(find.textContaining('note-1'), findsOneWidget);
    expect(
      find.textContaining('VALIDATION_ERROR'),
      findsOneWidget,
      reason: 'the reason must be visible, not just the fact of failure',
    );
    expect(find.text('From this device'), findsOneWidget);
  });

  testWidgets('an inbound failure is shown and labelled separately', (
    tester,
  ) async {
    await db.recordRemoteOpFailure(
      opId: 'remote-1',
      entityType: 'prayer',
      entityId: 'prayer-9',
      error: 'SqliteException: disk full',
      now: 2000,
    );
    await db.deadLetterRemoteOp('remote-1');

    await pump(tester);

    expect(find.text('Changes needing attention'), findsOneWidget);
    expect(find.textContaining('prayer-9'), findsOneWidget);
    expect(find.text('From another device'), findsOneWidget);
    expect(
      find.textContaining('re-checks your whole account'),
      findsOneWidget,
      reason: 'retrying an inbound item needs a full resync, and the user '
          'should know that before tapping',
    );
  });

  testWidgets('both directions appear together', (tester) async {
    await db.into(db.oplog).insert(
      OplogCompanion.insert(
        opId: 'op-1',
        entityType: 'note',
        entityId: 'note-1',
        operation: 'UPDATE',
        payloadJson: '{}',
        timestamp: 1,
        deviceId: 'd1',
        entityVersion: 1,
        failedAt: const Value(1000),
        failedReason: const Value('VALIDATION_ERROR'),
      ),
    );
    await db.recordRemoteOpFailure(
      opId: 'remote-1',
      entityType: 'prayer',
      entityId: 'prayer-9',
      error: 'disk full',
      now: 2000,
    );
    await db.deadLetterRemoteOp('remote-1');

    await pump(tester);

    expect(find.text('From this device'), findsOneWidget);
    expect(find.text('From another device'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });
}
