// The Prayers tab is the dashboard, and its rows only had a long-press menu: no
// swipe, unlike notes, songs and promises. Swiping a prayer left now shows the
// same "Trash" action, and it trashes the same way the menu does.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:notify/core/domain/enums/prayer_enums.dart';
import 'package:notify/core/sync/models/person_model.dart';
import 'package:notify/core/sync/models/prayer_model.dart';
import 'package:notify/core/sync/providers/sync_providers.dart';
import 'package:notify/core/sync/repositories/prayer_repository.dart';
import 'package:notify/core/theme/app_theme.dart';
import 'package:notify/features/prayers/presentation/screens/prayers_dashboard_screen.dart';
import 'package:notify/l10n/app_localizations.dart';

class _FakePrayers extends Fake implements PrayerRepository {
  final trashed = <String>[];
  final restored = <String>[];

  @override
  Future<PrayerModel> trashPrayer(String id) async {
    trashed.add(id);
    return _prayer(id, 'trashed');
  }

  @override
  Future<PrayerModel> restorePrayer(String id) async {
    restored.add(id);
    return _prayer(id, 'restored');
  }
}

PrayerModel _prayer(String id, String title) => PrayerModel(
      id: id,
      userId: 'u1',
      title: title,
      content: 'Lord, hear us.',
      frequency: PrayerFrequency.daily,
      status: PrayerStatus.active,
      category: 'personal',
      answeredAt: null,
      updatedAt: 1,
      version: 1,
      deleted: 0,
      createdAt: 1,
    );

void main() {
  late _FakePrayers repo;

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(402, 874) * 3;
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    repo = _FakePrayers();

    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        prayerRepositoryProvider.overrideWithValue(repo),
        prayersStreamProvider.overrideWith((ref) => Stream.value([
              _prayer('p1', 'Healing for Ann'),
              _prayer('p2', 'Wisdom at work'),
            ])),
        peopleStreamProvider
            .overrideWith((ref) => Stream.value(const <PersonModel>[])),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const PrayersDashboardScreen(),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('swiping a prayer shows the same Trash action as the others',
      (tester) async {
    await pump(tester);

    await tester.drag(find.text('Healing for Ann'), const Offset(-300, 0));
    await tester.pumpAndSettle();

    expect(find.text('Trash'), findsOneWidget);
    expect(find.byIcon(Icons.delete_outline_rounded), findsOneWidget);
    expect(find.text('Move to trash'), findsNothing,
        reason: 'the swipe word is "Trash"');
  });

  testWidgets('the Trash action asks first, then trashes that prayer',
      (tester) async {
    await pump(tester);

    await tester.drag(find.text('Healing for Ann'), const Offset(-300, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Trash'));
    await tester.pumpAndSettle();

    // The confirmation, as with the long-press menu.
    expect(find.text('Move to trash'), findsWidgets);
    expect(repo.trashed, isEmpty, reason: 'not before it is confirmed');

    await tester.tap(find.widgetWithText(TextButton, 'Move to trash'));
    await tester.pumpAndSettle();

    expect(repo.trashed, ['p1']);
  });

  testWidgets('cancelling the confirmation trashes nothing', (tester) async {
    await pump(tester);

    await tester.drag(find.text('Wisdom at work'), const Offset(-300, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Trash'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(repo.trashed, isEmpty);
  });

  testWidgets('the undo that follows puts the prayer back', (tester) async {
    await pump(tester);

    await tester.drag(find.text('Healing for Ann'), const Offset(-300, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Trash'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Move to trash'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();

    expect(repo.restored, ['p1']);
  });

  testWidgets('tapping a row still opens it (the swipe did not take the tap)',
      (tester) async {
    await pump(tester);
    // No router in this harness: a tap reaches onTap and fails on the missing
    // GoRouter, which is how we know the tap got through to the card.
    await tester.tap(find.text('Healing for Ann'));
    await tester.pump();
    expect(tester.takeException(), isNotNull);
  });
}
