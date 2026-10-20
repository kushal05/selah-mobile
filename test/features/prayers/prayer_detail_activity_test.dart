// The prayer page: one-tap logging, and the rolling "Prayed N times" entry in
// its Activity.
//
// Logging used to open a sheet for a note nothing ever showed, and the page
// never said how often the prayer had been prayed. Now a tap logs it, with
// Undo, and Activity carries one entry — "Prayed 15 times", beside the last
// time — rewritten in place on every log rather than one entry per log.
// Driven over a real database; only the server-backed sharing providers are
// stubbed.

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:notify/core/database/sync_database.dart';
import 'package:notify/core/sync/models/group_model.dart';
import 'package:notify/core/sync/models/prayer_collaborator_model.dart';
import 'package:notify/core/sync/providers/sync_providers.dart';
import 'package:notify/core/theme/app_theme.dart';
import 'package:notify/features/prayers/presentation/screens/prayer_detail_screen.dart';
import 'package:notify/l10n/l10n.dart';

final _logAction = find.text('Log prayer');
final _undo = find.widgetWithText(SnackBarAction, 'Undo');
final _prayedEntry = find.textContaining(RegExp(r'^Prayed (once|\d+ times)$'));

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  late SyncDatabase db;
  late ProviderContainer container;
  late String prayerId;

  Future<void> settleDb(WidgetTester tester, [int rounds = 4]) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> pumpPage(WidgetTester tester,
      {String content = 'For her recovery.'}) async {
    tester.view.physicalSize = const Size(390 * 3, 2400 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    db = SyncDatabase.forTesting(NativeDatabase.memory());
    addTearDown(() => tester.runAsync(db.close));
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    container = ProviderContainer(overrides: [
      syncDatabaseProvider.overrideWithValue(db),
      currentUserIdProvider.overrideWith((ref) => 'u1'),
      sharedPreferencesProvider.overrideWithValue(prefs),
      sharedPrayerProvider.overrideWith((ref, id) async => null),
      prayerCollaboratorsProvider
          .overrideWith((ref, id) async => const <PrayerCollaboratorModel>[]),
      groupsListProvider.overrideWith((ref) async => const <GroupModel>[]),
    ]);
    addTearDown(container.dispose);

    await tester.runAsync(() async {
      prayerId = (await container.read(prayerRepositoryProvider).createPrayer(
                userId: 'u1',
                title: 'Healing for Mom',
                content: content,
              ))
          .id;
    });

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: PrayerDetailScreen(prayerId: prayerId),
      ),
    ));
    await settleDb(tester);
    expect(find.text('Prayer created'), findsOneWidget,
        reason: 'precondition: the Activity section is on screen');
  }

  /// One deliberate log: tap, let it land, then wait out the moment after a
  /// log in which the button ignores taps (a double tap's second tap).
  Future<void> logOnce(WidgetTester tester) async {
    await tester.ensureVisible(_logAction);
    await tester.tap(_logAction);
    await settleDb(tester);
    await tester.pump(const Duration(seconds: 2));
  }

  testWidgets('a prayer never logged has no Prayed entry', (tester) async {
    await pumpPage(tester);
    expect(_prayedEntry, findsNothing);
  });

  testWidgets('one tap logs it — no sheet — and offers Undo', (tester) async {
    await pumpPage(tester);
    await tester.ensureVisible(_logAction);
    await tester.tap(_logAction);
    await tester.pump();
    expect(find.byType(BottomSheet), findsNothing);
    await settleDb(tester);

    expect(find.text('Prayer logged'), findsOneWidget);
    expect(_undo, findsOneWidget);
    expect(find.text('Prayed once'), findsOneWidget);
  });

  testWidgets('each log rewrites the one entry instead of adding another',
      (tester) async {
    await pumpPage(tester);
    await logOnce(tester);
    await logOnce(tester);
    await logOnce(tester);
    expect(_prayedEntry, findsOneWidget);
    expect(find.text('Prayed 3 times'), findsOneWidget);
  });

  testWidgets('Undo takes the count back down', (tester) async {
    await pumpPage(tester);
    await logOnce(tester);
    await logOnce(tester);
    expect(find.text('Prayed 2 times'), findsOneWidget);

    // A snackbar ignores taps while it slides in, and the second log's has
    // only just replaced the first's.
    await tester.pumpAndSettle();
    await tester.tap(_undo);
    await settleDb(tester);
    expect(find.text('Prayed once'), findsOneWidget);
    expect(find.text('Log removed'), findsOneWidget);
  });

  testWidgets('sits in the timeline by its last-prayed time', (tester) async {
    await pumpPage(tester);
    final updates = container.read(prayerUpdateRepositoryProvider);
    Future<void> addUpdate(String text) async {
      await tester.runAsync(() async {
        await updates.addUpdate(
            prayerId: prayerId, userId: 'u1', content: text);
        // Distinct millisecond timestamps for the ordering.
        await Future<void>.delayed(const Duration(milliseconds: 5));
      });
      await settleDb(tester, 2);
    }

    await addUpdate('Surgery is booked');
    await logOnce(tester);
    double y(Finder f) => tester.getTopLeft(f).dy;
    expect(y(_prayedEntry), lessThan(y(find.text('Surgery is booked'))),
        reason: 'prayed after the update, so above it');

    await addUpdate('Surgery went well');
    expect(y(find.text('Surgery went well')), lessThan(y(_prayedEntry)),
        reason: 'a newer update goes above it');
    expect(y(_prayedEntry), lessThan(y(find.text('Prayer created'))));
  });

  testWidgets('Add update opens the shared sheet and the update lands in '
      'Activity', (tester) async {
    await pumpPage(tester);
    final addUpdate = find.widgetWithText(OutlinedButton, 'Add update');
    await tester.ensureVisible(addUpdate);
    await tester.tap(addUpdate);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).last, 'Surgery went well');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pumpAndSettle();
    await settleDb(tester);

    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('Surgery went well'), findsOneWidget);
  });

  testWidgets('a quick double tap on Log prayer logs it once', (tester) async {
    // The old sheet was modal, which happened to stop the second tap. The
    // write lands in milliseconds, before a double tap's second tap, so the
    // button holds off for a moment after each log too.
    await pumpPage(tester);
    await tester.ensureVisible(_logAction);
    await tester.tap(_logAction);
    await settleDb(tester); // the first log has landed...
    await tester.tap(_logAction); // ...and the second tap of the pair arrives
    await settleDb(tester);
    expect(find.text('Prayed once'), findsOneWidget);
  });

  testWidgets('two taps landing in the same frame log it once',
      (tester) async {
    // Dimming the button only takes effect at the next frame; until then both
    // taps reach the live button, and _logPrayer's own check is what stops the
    // second.
    await pumpPage(tester);
    await tester.ensureVisible(_logAction);
    await tester.tap(_logAction);
    await tester.tap(_logAction); // no pump between: same frame
    await settleDb(tester);
    expect(find.text('Prayed once'), findsOneWidget);
  });

  testWidgets('the button is dimmed during the pause and back after it',
      (tester) async {
    await pumpPage(tester);
    bool live() => tester
            .widget<InkWell>(find
                .ancestor(of: _logAction, matching: find.byType(InkWell))
                .first)
            .onTap !=
        null;
    expect(live(), isTrue);
    await tester.ensureVisible(_logAction);
    await tester.tap(_logAction);
    await settleDb(tester);
    expect(live(), isFalse, reason: 'shows that a tap now would do nothing');
    await tester.pump(const Duration(seconds: 2));
    expect(live(), isTrue);
  });

  testWidgets('Undo ends the pause, so a corrected log can follow at once',
      (tester) async {
    await pumpPage(tester);
    await tester.ensureVisible(_logAction);
    await tester.tap(_logAction);
    await settleDb(tester);
    await tester.pumpAndSettle(); // the snackbar ignores taps as it slides in
    await tester.tap(_undo);
    await settleDb(tester);
    expect(_prayedEntry, findsNothing);

    await tester.tap(_logAction); // well inside the two seconds
    await settleDb(tester);
    expect(find.text('Prayed once'), findsOneWidget);
  });

  testWidgets('and a deliberate second log, moments later, still counts',
      (tester) async {
    await pumpPage(tester);
    await logOnce(tester); // waits out the pause after a log
    await logOnce(tester);
    expect(find.text('Prayed 2 times'), findsOneWidget);
  });

  group('updates from before they had their own table', () {
    // Stored oldest first, after this separator in the prayer's content.
    String legacy(String updatesJson) =>
        'For her recovery.\n<!-- updates -->\n$updatesJson';

    testWidgets('read newest first by their timestamps', (tester) async {
      await pumpPage(tester,
          content: legacy('[{"text":"Older","timestamp":1000},'
              '{"text":"Newer","timestamp":2000}]'));
      expect(tester.getTopLeft(find.text('Newer')).dy,
          lessThan(tester.getTopLeft(find.text('Older')).dy));
    });

    testWidgets('and newest first when they have none', (tester) async {
      await pumpPage(tester,
          content: legacy('[{"text":"First"},{"text":"Second"}]'));
      expect(tester.getTopLeft(find.text('Second')).dy,
          lessThan(tester.getTopLeft(find.text('First')).dy));
    });
  });
}
