// A splash that cannot be seen.
//
// An InkWell (and so a ListTile) paints its splash on the nearest Material. If
// a Container with a background sits between the two, that background is drawn
// over the splash and a tap shows nothing at all. These rows were like that;
// each now has a Material of its own inside the coloured container.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:notify/core/sync/providers/sync_providers.dart';
import 'package:notify/core/theme/app_theme.dart';
import 'package:notify/features/friends/presentation/screens/friends_list_screen.dart';
import 'package:notify/features/friends/presentation/screens/profile_settings_screen.dart';
import 'package:notify/l10n/app_localizations.dart';

/// Every InkWell under the tree whose nearest Material is behind a coloured
/// box, described for the failure message.
List<String> hiddenSplashes(WidgetTester tester) {
  final found = <String>[];
  for (final element in find.byType(InkWell).evaluate()) {
    var reachedMaterial = false;
    String? cover;
    element.visitAncestorElements((ancestor) {
      final w = ancestor.widget;
      if (w is Material) {
        reachedMaterial = true;
        return false;
      }
      if (w is DecoratedBox) {
        final d = w.decoration;
        if (d is BoxDecoration &&
            ((d.color != null && d.color!.a > 0) || d.gradient != null)) {
          cover ??= 'a coloured box ($d)';
        }
      }
      return true;
    });
    if (reachedMaterial && cover != null) {
      found.add('${(element.widget as InkWell).child.runtimeType} under $cover');
    }
  }
  return found;
}

Future<void> _pump(
  WidgetTester tester,
  Widget screen, {
  List<Override> overrides = const [],
}) async {
  tester.view.physicalSize = const Size(420, 900) * 2;
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      ...overrides,
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: screen,
    ),
  ));
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets('the checker itself sees a hidden splash', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Container(
          decoration: const BoxDecoration(color: Colors.white),
          child: InkWell(onTap: () {}, child: const Text('row')),
        ),
      ),
    ));
    expect(hiddenSplashes(tester), isNotEmpty);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Container(
          decoration: const BoxDecoration(color: Colors.white),
          child: Material(
            color: Colors.transparent,
            child: InkWell(onTap: () {}, child: const Text('row')),
          ),
        ),
      ),
    ));
    expect(hiddenSplashes(tester), isEmpty);
  });

  testWidgets('the pending-requests banner shows its splash', (tester) async {
    await _pump(
      tester,
      const FriendsListScreen(),
      overrides: [
        friendsListProvider.overrideWith((ref) async => const []),
        pendingRequestCountProvider.overrideWith((ref) async => 3),
      ],
    );

    expect(find.textContaining('3 pending request'), findsOneWidget);
    expect(hiddenSplashes(tester), isEmpty);
  });

  testWidgets('profile settings rows show their splash', (tester) async {
    await _pump(
      tester,
      const ProfileSettingsScreen(),
      overrides: [
        blockedUsersProvider.overrideWith((ref) async => const []),
      ],
    );
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(ListTile), findsWidgets);
    expect(hiddenSplashes(tester), isEmpty);
  });
}
