// A count nobody could read is not a count of zero.
//
// Both widgets here took a non-nullable value fed by `valueOrNull ?? 0` or
// `?? {}`, so a failed read rendered as "0 notes" and an empty ninety-one-day
// grid — which is exactly what a folder with nothing in it and a habit nobody
// has ever done look like. The types are nullable now; these pin what null
// renders as, because making the type honest and leaving the widget drawing
// the same thing would fix nothing.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:notify/core/theme/app_theme.dart';
import 'package:notify/features/habits/data/habit_log_repository.dart';
import 'package:notify/features/habits/presentation/widgets/habit_heatmap_widget.dart';
import 'package:notify/l10n/l10n.dart';
import 'package:notify/shared/widgets/lists/folder_row.dart';

Future<void> _pump(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(900, 1400);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  group('a folder whose notes could not be counted', () {
    testWidgets('does not claim zero', (tester) async {
      await _pump(
        tester,
        const FolderRow(
          title: 'Sermons',
          noteCount: null,
          depth: 0,
          hasChildren: false,
          isExpanded: false,
          isActive: false,
          // The read failed, which is what this group is about. A null count
          // on its own means only "not known", and that is also true for the
          // frames between opening the screen and the notes arriving.
          countFailed: true,
        ),
      );

      expect(find.textContaining('0 notes'), findsNothing);
      expect(find.textContaining('Count unavailable'), findsOneWidget);
    });

    testWidgets('but a count still on its way says nothing', (tester) async {
      await _pump(
        tester,
        const FolderRow(
          title: 'Sermons',
          noteCount: null,
          depth: 0,
          hasChildren: false,
          isExpanded: false,
          isActive: false,
        ),
      );

      expect(find.textContaining('Count unavailable'), findsNothing,
          reason: 'every cold open passes through this state');
      expect(find.textContaining('0 notes'), findsNothing);
    });

    testWidgets('and a folder that genuinely holds none still says zero', (
      tester,
    ) async {
      // The counterpart: without it, a widget that had stopped rendering counts
      // altogether would satisfy the assertion above.
      await _pump(
        tester,
        const FolderRow(
          title: 'Sermons',
          noteCount: 0,
          depth: 0,
          hasChildren: false,
          isExpanded: false,
          isActive: false,
        ),
      );

      expect(find.textContaining('0 notes'), findsOneWidget);
      expect(find.textContaining('Count unavailable'), findsNothing);
    });
  });

  group('a habit whose history could not be read', () {
    testWidgets('says so instead of drawing an empty grid', (tester) async {
      await _pump(
        tester,
        const HabitHeatmapWidget(
          habit: HabitType.bible,
          color: AppTheme.emerald,
          completedDays: null,
          // `failed` because that is what this group is about. A null history
          // alone means only "not known", which is also true for the moment
          // between opening the screen and the query returning — and the
          // widget stays silent there rather than announcing a failure it
          // would have to retract.
          failed: true,
        ),
      );

      expect(find.text('History unavailable'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('but a read still in flight says nothing', (tester) async {
      await _pump(
        tester,
        const HabitHeatmapWidget(
          habit: HabitType.bible,
          color: AppTheme.emerald,
          completedDays: null,
        ),
      );

      expect(find.text('History unavailable'), findsNothing,
          reason: 'every cold open passes through this state');
      expect(tester.takeException(), isNull);
    });

    testWidgets('and a genuinely empty history still draws the grid', (
      tester,
    ) async {
      await _pump(
        tester,
        const HabitHeatmapWidget(
          habit: HabitType.bible,
          color: AppTheme.emerald,
          completedDays: <int>{},
        ),
      );

      expect(find.text('History unavailable'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
