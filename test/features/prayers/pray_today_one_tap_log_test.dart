// Logging a prayer is one tap, with Undo.
//
// It used to open a sheet asking how the prayer went. The note it collected
// was stored and synced but never shown anywhere, so every log cost a second
// tap — and the home-screen widget's ✓ opened the app onto a form — for text
// nobody could read back. Driven through the real screen over a real database,
// so the tests see the log actually written and actually removed.

import 'dart:async';

import 'package:drift/drift.dart' show Variable, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:notify/core/database/sync_database.dart';
import 'package:notify/core/navigation/routes.dart';
import 'package:notify/core/sync/models/prayer_log_model.dart';
import 'package:notify/core/sync/repositories/prayer_log_repository.dart';
import 'package:notify/core/sync/providers/sync_providers.dart';
import 'package:notify/core/theme/app_theme.dart';
import 'package:notify/features/prayers/presentation/screens/pray_today_screen.dart';
import 'package:notify/features/prayers/presentation/widgets/pray_today_card.dart';
import 'package:notify/l10n/l10n.dart';

final _logButton = find.byTooltip('Log prayer');
final _loggedButton = find.byTooltip('Prayed');
final _undo = find.widgetWithText(SnackBarAction, 'Undo');

/// The log button on the card of the prayer titled [title].
Finder _logButtonOf(String title) => find.descendant(
    of: find.ancestor(
        of: find.text(title), matching: find.byType(PrayTodayCard)),
    matching: _logButton);

/// The real repository, with each write held until [release] completes — the
/// gap between the tap and the card showing the prayer logged, which on a
/// device lasts as long as the write takes.
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
  late List<String> prayerIds;

  /// Lets drift's real-time work land, pumping frames in between.
  Future<void> settleDb(WidgetTester tester, [int rounds = 4]) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> pumpScreen(
    WidgetTester tester, {
    List<String> titles = const ['Healing for Mom', 'Wisdom at work'],
    String? Function(List<String> ids)? logPrayerId,
    _HeldLogRepository Function(SyncDatabase db)? logRepo,
  }) async {
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
      prayerIds = [
        for (final t in titles)
          (await container.read(prayerRepositoryProvider).createPrayer(
                userId: 'u1',
                title: t,
                content: 'For $t.',
              ))
              .id,
      ];
    });

    final router = GoRouter(routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => Scaffold(
            body: PrayTodayScreen(logPrayerId: logPrayerId?.call(prayerIds))),
      ),
      GoRoute(
          path: Routes.habits,
          builder: (_, _) => const Text('HABITS SCREEN')),
      GoRoute(
          path: Routes.prayerAnalytics,
          builder: (_, _) => const Text('ANALYTICS SCREEN')),
    ]);
    addTearDown(router.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    ));
    await settleDb(tester);
  }

  /// (note, deleted) for every log of [prayerId].
  Future<List<(String, int)>> logs(WidgetTester tester, String prayerId) async =>
      (await tester.runAsync(() => db
              .customSelect(
                  'SELECT note, deleted FROM prayer_logs WHERE prayer_id = ?',
                  variables: [Variable.withString(prayerId)])
              .get()))!
          .map((r) => (r.read<String>('note'), r.read<int>('deleted')))
          .toList();

  testWidgets('one tap logs the prayer — no sheet, no dialog', (tester) async {
    await pumpScreen(tester);
    await tester.tap(_logButtonOf('Healing for Mom'));
    await tester.pump();
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);

    await settleDb(tester);
    expect(await logs(tester, prayerIds.first), [('', 0)]);
    expect(_loggedButton, findsOneWidget, reason: 'the card shows it prayed');
    expect(find.text('Prayer logged'), findsOneWidget);
  });

  testWidgets('Undo removes the log and the card is unlogged again',
      (tester) async {
    await pumpScreen(tester);
    await tester.tap(_logButtonOf('Healing for Mom'));
    await settleDb(tester);

    await tester.tap(_undo);
    await settleDb(tester);

    expect(await logs(tester, prayerIds.first), [('', 1)],
        reason: 'soft-deleted, so the removal syncs');
    expect(_loggedButton, findsNothing);
    expect(_logButton, findsNWidgets(2));
    expect(find.text('Log removed'), findsOneWidget);
  });

  testWidgets('undoing the last prayer brings the list back from the finish',
      (tester) async {
    await pumpScreen(tester, titles: ['Healing for Mom']);
    await tester.tap(_logButton);
    await settleDb(tester);
    expect(find.text('View progress in Habits'), findsOneWidget,
        reason: 'precondition: every prayer logged, so the finish screen');

    await tester.tap(_undo);
    await settleDb(tester);
    expect(find.text('View progress in Habits'), findsNothing);
    expect(_logButton, findsOneWidget);
  });

  testWidgets('a second tap while the log is being written does nothing',
      (tester) async {
    late _HeldLogRepository repo;
    await pumpScreen(tester,
        logRepo: (db) => repo = _HeldLogRepository(db, 'device-1'));

    await tester.tap(_logButtonOf('Healing for Mom'));
    await tester.pump();
    // The write is held: the card still shows the prayer unlogged and its
    // button still answers.
    await tester.tap(_logButtonOf('Healing for Mom'));
    await tester.pump();
    expect(repo.calls, 1);

    repo.release.complete();
    await settleDb(tester);
    expect(repo.calls, 1);
    expect(await logs(tester, prayerIds.first), [('', 0)], reason: 'once');
  });

  testWidgets("the home-screen widget's ✓ logs on arrival, without a form",
      (tester) async {
    await pumpScreen(tester, logPrayerId: (ids) => ids.last);
    expect(find.byType(BottomSheet), findsNothing);
    expect(await logs(tester, prayerIds.last), [('', 0)]);
    expect(await logs(tester, prayerIds.first), isEmpty);
    expect(_undo, findsOneWidget, reason: 'a mistaken widget tap can be undone');
  });

  group('the finish screen', () {
    Future<void> finish(WidgetTester tester) async {
      await pumpScreen(tester, titles: ['Healing for Mom']);
      await tester.tap(_logButton);
      await settleDb(tester);
      ScaffoldMessenger.of(tester.element(find.byType(Scaffold).first))
          .clearSnackBars();
      await tester.pumpAndSettle();
    }

    testWidgets('says the progress is in Habits and opens it', (tester) async {
      await finish(tester);
      expect(find.text('Your progress is updated in Habits.'), findsOneWidget);
      await tester.tap(find.text('View progress in Habits'));
      await tester.pumpAndSettle();
      expect(find.text('HABITS SCREEN'), findsOneWidget);
    });

    testWidgets('Review logs opens Prayer analytics', (tester) async {
      await finish(tester);
      await tester.tap(find.text('Review logs'));
      await tester.pumpAndSettle();
      expect(find.text('ANALYTICS SCREEN'), findsOneWidget);
    });

    testWidgets('no longer offers a reflection that is thrown away',
        (tester) async {
      await finish(tester);
      expect(find.text('Add a reflection'), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);
    });
  });
}
