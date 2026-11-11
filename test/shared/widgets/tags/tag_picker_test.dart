// Tags, wherever they are picked: a few lines of chips A to Z, the rest behind
// "Show more tags", which opens a dialog of every tag to tick any number of,
// with "Add tag" fixed at the top while the list scrolls.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:notify/core/theme/app_theme.dart';
import 'package:notify/l10n/app_localizations.dart';
import 'package:notify/shared/widgets/selectable_chip.dart';
import 'package:notify/shared/widgets/tags/tag_picker_dialog.dart';
import 'package:notify/shared/widgets/tags/tag_picker_field.dart';

Widget _app(Widget child) => MaterialApp(
      theme: AppTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

List<TagOption> _tags(int n) => [
      for (var i = n; i >= 1; i--)
        TagOption('id$i', 'Tag ${i.toString().padLeft(2, '0')}'),
    ]; // deliberately in reverse order

void main() {
  group('chipsThatFit', () {
    test('everything fits on one line', () {
      expect(
          chipsThatFit(
              widths: [50, 50, 50], maxWidth: 200, spacing: 8, maxLines: 4),
          3);
    });

    test('wraps the way Wrap does', () {
      // 100 + 8 + 100 = 208 > 200, so every chip starts a line of its own.
      expect(
          chipsThatFit(
              widths: [100, 100, 100], maxWidth: 200, spacing: 8, maxLines: 3),
          3);
      expect(
          chipsThatFit(
              widths: [100, 100, 100], maxWidth: 200, spacing: 8, maxLines: 2),
          2);
      expect(
          chipsThatFit(
              widths: [100, 100, 100], maxWidth: 200, spacing: 8, maxLines: 1),
          1);
      // 100 + 8 + 90 = 198 fits beside it.
      expect(
          chipsThatFit(
              widths: [100, 90, 100], maxWidth: 200, spacing: 8, maxLines: 1),
          2);
    });

    test('stops at the line limit', () {
      // Two chips per line of 200: lines of 2, so 4 lines hold 8.
      expect(
          chipsThatFit(
              widths: List.filled(20, 90.0),
              maxWidth: 200,
              spacing: 8,
              maxLines: 4),
          8);
    });

    test('a chip wider than the line gets a line of its own', () {
      expect(
          chipsThatFit(
              widths: [500, 40, 40], maxWidth: 200, spacing: 8, maxLines: 2),
          3);
      expect(
          chipsThatFit(
              widths: [500, 40, 40], maxWidth: 200, spacing: 8, maxLines: 1),
          1);
    });

    test('nothing to show', () {
      expect(
          chipsThatFit(widths: [], maxWidth: 200, spacing: 8, maxLines: 4), 0);
    });
  });

  group('TagPickerField', () {
    testWidgets('a few tags show in full, with no "Show more tags"',
        (tester) async {
      await tester.pumpWidget(_app(TagPickerField(
        options: _tags(3),
        selected: const {},
        onChanged: (_) {},
      )));

      expect(find.byType(SelectableChip), findsNWidgets(3));
      expect(find.text('Show more tags'), findsNothing);
    });

    testWidgets('chips are A to Z', (tester) async {
      await tester.pumpWidget(_app(TagPickerField(
        options: _tags(4),
        selected: const {},
        onChanged: (_) {},
      )));

      final order = ['Tag 01', 'Tag 02', 'Tag 03', 'Tag 04'];
      final x = [for (final l in order) tester.getTopLeft(find.text(l))];
      for (var i = 1; i < x.length; i++) {
        final before = x[i - 1], after = x[i];
        expect(after.dy > before.dy || after.dx > before.dx, isTrue,
            reason: '${order[i]} should come after ${order[i - 1]}');
      }
    });

    testWidgets('many tags are held to four lines, the rest behind a button',
        (tester) async {
      tester.view.physicalSize = const Size(402, 874) * 3;
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_app(TagPickerField(
        options: _tags(60),
        selected: const {},
        onChanged: (_) {},
      )));

      final chips = tester.widgetList(find.byType(SelectableChip)).length;
      expect(chips, lessThan(60));
      expect(chips, greaterThan(0));

      final lines = {
        for (final e in find.byType(SelectableChip).evaluate())
          tester.getTopLeft(find.byWidget(e.widget)).dy.round(),
      };
      expect(lines.length, lessThanOrEqualTo(4));

      expect(find.text('Show more tags'), findsOneWidget);
    });

    testWidgets('tapping a chip reports the new selection', (tester) async {
      Set<String>? got;
      await tester.pumpWidget(_app(TagPickerField(
        options: _tags(3),
        selected: const {'id1'},
        onChanged: (s) => got = s,
      )));

      await tester.tap(find.text('Tag 02'));
      expect(got, {'id1', 'id2'});

      await tester.tap(find.text('Tag 01'));
      expect(got, isEmpty);
    });

    testWidgets('the button says how many hidden tags are ticked',
        (tester) async {
      tester.view.physicalSize = const Size(402, 874) * 3;
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      // Tag 60 sorts last, so it is hidden.
      await tester.pumpWidget(_app(TagPickerField(
        options: _tags(60),
        selected: const {'id60'},
        onChanged: (_) {},
      )));

      expect(find.text('Show more tags (1 selected)'), findsOneWidget);
    });

    testWidgets('the dialog result becomes the new selection', (tester) async {
      tester.view.physicalSize = const Size(402, 874) * 3;
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      Set<String>? got;
      await tester.pumpWidget(_app(TagPickerField(
        options: _tags(60),
        selected: const {},
        onChanged: (s) => got = s,
      )));

      await tester.tap(find.text('Show more tags'));
      await tester.pumpAndSettle();
      // The chip behind the dialog has the same name; tap the dialog's row.
      await tester.tap(find.descendant(
          of: find.byType(Dialog), matching: find.text('Tag 01')));
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      expect(got, {'id1'});
    });
  });

  group('TagPickerDialog', () {
    Future<void> open(
      WidgetTester tester, {
      required List<TagOption> options,
      Set<String> selected = const {},
      Future<TagOption?> Function(String)? onCreate,
      void Function(Set<String>?)? onResult,
    }) async {
      tester.view.physicalSize = const Size(402, 874) * 3;
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                final r = await TagPickerDialog.show(
                  context,
                  options: options,
                  selected: selected,
                  onCreate: onCreate,
                );
                onResult?.call(r);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('lists every tag A to Z', (tester) async {
      await open(tester, options: _tags(5));

      final tops = [
        for (var i = 1; i <= 5; i++)
          tester.getTopLeft(find.text('Tag 0$i')).dy,
      ];
      final sorted = [...tops]..sort();
      expect(tops, sorted);
    });

    testWidgets('sorting ignores case', (tester) async {
      await open(tester, options: const [
        TagOption('1', 'banana'),
        TagOption('2', 'Apple'),
        TagOption('3', 'cherry'),
      ]);

      expect(tester.getTopLeft(find.text('Apple')).dy,
          lessThan(tester.getTopLeft(find.text('banana')).dy));
      expect(tester.getTopLeft(find.text('banana')).dy,
          lessThan(tester.getTopLeft(find.text('cherry')).dy));
    });

    testWidgets('any number can be ticked, and Done returns them',
        (tester) async {
      Set<String>? result;
      await open(tester,
          options: _tags(5),
          selected: const {'id5'},
          onResult: (r) => result = r);

      await tester.tap(find.text('Tag 01'));
      await tester.tap(find.text('Tag 03'));
      await tester.tap(find.text('Tag 05')); // untick the one that was ticked
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      expect(result, {'id1', 'id3'});
    });

    testWidgets('Cancel returns nothing', (tester) async {
      var called = false;
      Set<String>? result = {'unset'};
      await open(tester, options: _tags(3), onResult: (r) {
        called = true;
        result = r;
      });

      await tester.tap(find.text('Tag 01'));
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(called, isTrue);
      expect(result, isNull);
    });

    testWidgets('"Add tag" stays put while the list scrolls', (tester) async {
      await open(tester,
          options: _tags(60), onCreate: (n) async => TagOption(n, n));

      final before = tester.getTopLeft(find.text('Add tag'));
      expect(find.text('Tag 60'), findsNothing,
          reason: 'off screen until scrolled to');

      await tester.drag(find.byType(ListView), const Offset(0, -2000));
      await tester.pumpAndSettle();

      expect(find.text('Tag 01'), findsNothing, reason: 'it did scroll');
      expect(tester.getTopLeft(find.text('Add tag')), before);
      // And it is above the list, not below it.
      expect(before.dy, lessThan(tester.getTopLeft(find.byType(ListView)).dy));
    });

    testWidgets('a tag added in the dialog is ticked and listed',
        (tester) async {
      Set<String>? result;
      await open(
        tester,
        options: const [TagOption('1', 'Bravo')],
        onCreate: (name) async => TagOption('new-$name', name),
        onResult: (r) => result = r,
      );

      await tester.tap(find.text('Add tag'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Alpha');
      await tester.tap(find.byIcon(Icons.check));
      await tester.pumpAndSettle();

      // In the list, A to Z (Alpha before Bravo), already ticked.
      expect(tester.getTopLeft(find.text('Alpha')).dy,
          lessThan(tester.getTopLeft(find.text('Bravo')).dy));
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      expect(result, {'new-Alpha'});
    });

    testWidgets('with nothing to create, there is no "Add tag"',
        (tester) async {
      await open(tester, options: _tags(3));
      expect(find.text('Add tag'), findsNothing);
    });

    testWidgets('no tags at all says so', (tester) async {
      await open(tester, options: const []);
      expect(find.text('No tags yet'), findsOneWidget);
    });
  });
}
