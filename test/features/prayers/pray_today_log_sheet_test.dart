// Logging from Pray Today uses the same sheet as the prayer's detail page.
//
// The detail page had been moved from a bare AlertDialog to LogPrayerSheet;
// Pray Today kept its own copy of the old dialog, so logging the same prayer
// looked different depending on where you did it. Both go through the one
// sheet now. Driven through the real screen over a real database, so the test
// sees the log actually written — not just a sheet appearing.

import 'dart:async';

import 'package:drift/drift.dart' show Variable, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:notify/core/database/sync_database.dart';
import 'package:notify/core/sync/models/prayer_log_model.dart';
import 'package:notify/core/sync/repositories/prayer_log_repository.dart';
import 'package:notify/core/sync/providers/sync_providers.dart';
import 'package:notify/core/theme/app_theme.dart';
import 'package:notify/features/prayers/presentation/screens/pray_today_screen.dart';
import 'package:notify/l10n/l10n.dart';

/// The shared sheet. Private to its file, so found by its type's name.
final _sheet = find.byWidgetPredicate(
    (w) => w.runtimeType.toString() == '_LogPrayerSheet');

final _logButton = find.byTooltip('Log prayer');

/// The real repository, with each write held until [release] completes — the
/// gap between the sheet closing and the card showing the prayer logged,
/// which on a device lasts as long as the write takes.
class _HeldLogRepository extends PrayerLogRepository {
  _HeldLogRepository(super.db, super.deviceId);
  final release = Completer<void>();
  var calls = 0;

  @override
  Future<PrayerLogModel> logPrayer({
    required String prayerId,
    required String userId,
    String note = '',
    String? sessionDate,
  }) async {
    calls++;
    await release.future;
    return super.logPrayer(
        prayerId: prayerId, userId: userId, note: note, sessionDate: sessionDate);
  }
}

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  late SyncDatabase db;
  late String prayerId;

  Future<void> pumpScreen(WidgetTester tester,
      {_HeldLogRepository Function(SyncDatabase db)? logRepo}) async {
    db = SyncDatabase.forTesting(NativeDatabase.memory());
    addTearDown(() => tester.runAsync(db.close));
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    final container = ProviderContainer(overrides: [
      syncDatabaseProvider.overrideWithValue(db),
      currentUserIdProvider.overrideWith((ref) => 'u1'),
      sharedPreferencesProvider.overrideWithValue(prefs),
      if (logRepo != null)
        prayerLogRepositoryProvider.overrideWithValue(logRepo(db)),
    ]);
    addTearDown(container.dispose);

    // Drift does its work on real time, not the test's fake clock.
    await tester.runAsync(() async {
      final p = await container.read(prayerRepositoryProvider).createPrayer(
            userId: 'u1',
            title: 'Healing for Mom',
            content: 'For her recovery.',
          );
      prayerId = p.id;
    });

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: PrayTodayScreen()),
      ),
    ));
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Healing for Mom'), findsOneWidget,
        reason: "precondition: today's prayer is on screen");
  }

  Future<List<String>> loggedNotes(WidgetTester tester) async =>
      (await tester.runAsync(() => db
              .customSelect('SELECT note FROM prayer_logs WHERE prayer_id = ?',
                  variables: [Variable.withString(prayerId)])
              .get()))!
          .map((r) => r.read<String>('note'))
          .toList();

  testWidgets('the log button opens the shared sheet, not a dialog',
      (tester) async {
    await pumpScreen(tester);

    await tester.tap(_logButton);
    await tester.pumpAndSettle();

    expect(_sheet, findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing,
        reason: "Pray Today's own dialog is gone");
  });

  testWidgets('and logging from it writes the note given', (tester) async {
    await pumpScreen(tester);
    await tester.tap(_logButton);
    await tester.pumpAndSettle();

    await tester.enterText(
        find.descendant(of: _sheet, matching: find.byType(TextField)),
        'Felt peace about it');
    await tester.tap(find.descendant(
        of: _sheet, matching: find.widgetWithText(FilledButton, 'Log prayer')));
    await tester.pumpAndSettle();
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pump();

    expect(_sheet, findsNothing);
    expect(await loggedNotes(tester), ['Felt peace about it']);
  });

  testWidgets('a second tap while the log is being written does nothing',
      (tester) async {
    late _HeldLogRepository repo;
    await pumpScreen(tester,
        logRepo: (db) => repo = _HeldLogRepository(db, 'device-1'));
    await tester.tap(_logButton);
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
        of: _sheet, matching: find.widgetWithText(FilledButton, 'Log prayer')));
    await tester.pumpAndSettle();
    expect(_sheet, findsNothing);

    // The write is held: the card still shows the prayer unlogged and its
    // button still answers.
    expect(repo.calls, 1);
    await tester.tap(_logButton);
    await tester.pumpAndSettle();
    expect(_sheet, findsNothing, reason: 'the sheet opened a second time');

    repo.release.complete();
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pump();
    expect(repo.calls, 1);
    expect(await loggedNotes(tester), [''], reason: 'logged once');

    // And once it has landed, logging is still guarded — by the card, which
    // now shows the prayer done.
    expect(_logButton, findsNothing);
  });

  testWidgets('and cancelling it logs nothing', (tester) async {
    await pumpScreen(tester);
    await tester.tap(_logButton);
    await tester.pumpAndSettle();

    await tester.tap(find.descendant(
        of: _sheet, matching: find.widgetWithText(TextButton, 'Cancel')));
    await tester.pumpAndSettle();
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));

    expect(await loggedNotes(tester), isEmpty);

    // And the prayer can still be logged: cancelling released the guard
    // against logging it twice.
    await tester.tap(_logButton);
    await tester.pumpAndSettle();
    expect(_sheet, findsOneWidget);
  });
}
