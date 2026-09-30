// Every surface the Groups screens paint has to belong to the active theme.
//
// `Theme.of(context).cardColor` is not derived from the colour scheme, and
// AppTheme.dark() is built with copyWith — so a field it did not name kept the
// light value. cardColor stayed Colors.white, and the twenty-three places that
// read it for a surface drew a white card on the dark ground. Groups was the
// worst affected with eleven of them; Friends and the prayer collaborators
// list had the rest.
//
// The check is on what is painted, not on which token was named, because the
// bug was invisible at the call site — `Theme.of(context).cardColor` reads like
// the correct thing to ask for.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:notify/core/domain/enums/group_enums.dart';
import 'package:notify/core/sync/models/group_model.dart';
import 'package:notify/core/sync/providers/sync_providers.dart';
import 'package:notify/core/theme/app_theme.dart';
import 'package:notify/features/groups/presentation/screens/group_detail_screen.dart';
import 'package:notify/features/groups/presentation/screens/groups_list_screen.dart';
import 'package:notify/l10n/l10n.dart';

GroupModel _group(String name) => GroupModel(
      id: 'g-$name',
      name: name,
      description: 'Weekday mornings',
      groupType: GroupType.prayerGroup,
      joinCode: 'ABC123',
      createdByUserId: 'u1',
      userId: 'u1',
      updatedAt: 0,
      version: 1,
      deleted: 0,
      createdAt: 0,
    );

/// Relative luminance, per WCAG. Enough to tell a light surface from a dark one.
double _luminance(Color c) {
  double channel(double v) => v <= 0.03928
      ? v / 12.92
      : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(c.r) +
      0.7152 * channel(c.g) +
      0.0722 * channel(c.b);
}

/// Opaque boxes light enough to read as a light-theme surface.
List<String> _lightSurfaces(WidgetTester tester) {
  final found = <String>[];
  void walk(RenderObject o) {
    if (o is RenderDecoratedBox) {
      final d = o.decoration;
      if (d is BoxDecoration) {
        final c = d.color;
        // Opaque only: a translucent tint over a dark ground stays dark, and
        // the accent tints this feature uses are all drawn at alpha 0.08–0.2.
        if (c != null && c.a > 0.9 && _luminance(c) > 0.3) {
          found.add('opaque light box: $c');
        }
      }
    }
    o.visitChildren(walk);
  }

  walk(tester.binding.renderViews.first);
  return found;
}

Future<void> _pumpGroupsList(WidgetTester tester, ThemeData theme) async {
  tester.view.physicalSize = const Size(840, 1800);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        groupsListProvider.overrideWith((ref) async => [
              _group('Morning Prayer'),
              _group('Youth'),
            ]),
      ],
      child: MaterialApp(
        // Keyed so a second pumpWidget in one test cannot reuse the subtree
        // built under the first theme — that is how a dark-mode assertion
        // comes to compare light against light.
        key: ValueKey(theme.brightness),
        theme: theme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const GroupsListScreen(),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  _detailTests();

  testWidgets('the groups list paints no light surface in dark mode', (
    tester,
  ) async {
    await _pumpGroupsList(tester, AppTheme.dark());

    expect(_lightSurfaces(tester), isEmpty,
        reason: 'a card drawn from cardColor rather than the colour scheme');
    expect(tester.takeException(), isNull);
  });

  testWidgets('and the same screen in light mode does paint one', (
    tester,
  ) async {
    // The counterpart, so the check above cannot pass by finding no boxes at
    // all — a selector that matched nothing would satisfy it silently.
    await _pumpGroupsList(tester, AppTheme.light());

    expect(_lightSurfaces(tester), isNotEmpty,
        reason: 'the light theme must still draw light cards; if this fails '
            'the walk is finding nothing and the dark assertion is vacuous');
  });

  test('cardColor belongs to its theme, and matches context.cardSurface', () {
    // The root cause, asserted directly: dark() is a copyWith of light(), so
    // any colour field it does not name silently keeps the light value.
    expect(AppTheme.dark().cardColor, AppTheme.dark().colorScheme.surface);
    expect(AppTheme.light().cardColor, AppTheme.light().colorScheme.surface);
    expect(AppTheme.dark().cardColor, isNot(AppTheme.light().cardColor));
  });

  test('no opaque theme surface is the wrong shade for its theme', () {
    // Swept rather than spot-checked: cardColor was one of several fields that
    // ThemeData does not derive from the colour scheme, and the next one to go
    // wrong will not be cardColor.
    final checks = <String, (Color light, Color dark)>{
      'scaffoldBackgroundColor': (
        AppTheme.light().scaffoldBackgroundColor,
        AppTheme.dark().scaffoldBackgroundColor,
      ),
      'canvasColor': (AppTheme.light().canvasColor, AppTheme.dark().canvasColor),
      'cardColor': (AppTheme.light().cardColor, AppTheme.dark().cardColor),
      'colorScheme.surface': (
        AppTheme.light().colorScheme.surface,
        AppTheme.dark().colorScheme.surface,
      ),
    };
    final wrong = <String>[];
    checks.forEach((name, pair) {
      if (pair.$1.a > 0.9 && _luminance(pair.$1) < 0.3) {
        wrong.add('$name is dark in the light theme');
      }
      if (pair.$2.a > 0.9 && _luminance(pair.$2) > 0.3) {
        wrong.add('$name is light in the dark theme');
      }
    });
    expect(wrong, isEmpty);
  });
}

// ─── The group's own pages ────────────────────────────────────────────────────

Future<void> _pumpGroupDetail(WidgetTester tester, ThemeData theme) async {
  tester.view.physicalSize = const Size(840, 2000);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        groupByIdProvider('g1').overrideWith((ref) async => _group('Youth')),
        groupMembersProvider('g1').overrideWith((ref) async => const []),
        groupPrayersProvider('g1').overrideWith((ref) async => const []),
        groupAnnouncementsProvider('g1').overrideWith((ref) async => const []),
        prayersStreamProvider.overrideWith((ref) => Stream.value(const [])),
      ],
      child: MaterialApp(
        key: ValueKey(theme.brightness),
        theme: theme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const GroupDetailScreen(groupId: 'g1'),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 600));
}

/// Every tab, because the screen opens on Overview and the report named the
/// feed and the prayers list — one pump only ever renders the first one.
const _tabs = ['Overview', 'Feed', 'Prayers', 'Announcements', 'Members', 'Info'];

void _detailTests() {
  for (final tab in _tabs) {
    testWidgets('the $tab tab paints no light surface in dark mode', (
      tester,
    ) async {
      await _pumpGroupDetail(tester, AppTheme.dark());
      // Scoped to the Tab: "Prayers" and "Members" also label stat chips on
      // the Overview tab, so a bare text finder matches two widgets and throws.
      await tester.tap(find.widgetWithText(Tab, tab));
      await tester.pump(const Duration(milliseconds: 600));

      expect(_lightSurfaces(tester), isEmpty,
          reason: 'a surface drawn from cardColor rather than the scheme');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('and the same page in light mode does paint light surfaces', (
    tester,
  ) async {
    // The counterpart: without it, a walk that silently found no boxes would
    // satisfy all six assertions above.
    await _pumpGroupDetail(tester, AppTheme.light());
    expect(_lightSurfaces(tester), isNotEmpty);
  });
}
