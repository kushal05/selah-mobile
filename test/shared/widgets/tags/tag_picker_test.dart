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

    testWidgets('the search box stays put while the list scrolls',
        (tester) async {
      await open(tester, options: _tags(60));

      final before = tester.getTopLeft(find.byKey(const Key('tag-search')));
      expect(find.text('Tag 60'), findsNothing,
          reason: 'off screen until scrolled to');

      await tester.drag(find.byType(ListView), const Offset(0, -2000));
      await tester.pumpAndSettle();

      expect(find.text('Tag 01'), findsNothing, reason: 'it did scroll');
      expect(tester.getTopLeft(find.byKey(const Key('tag-search'))), before);
      // And it is above the list, not below it.
      expect(before.dy, lessThan(tester.getTopLeft(find.byType(ListView)).dy));
    });

    testWidgets('a tag created in the dialog is ticked and listed A to Z',
        (tester) async {
      Set<String>? result;
      await open(
        tester,
        options: const [TagOption('1', 'Bravo')],
        onCreate: (name) async => TagOption('new-$name', name),
        onResult: (r) => result = r,
      );

      await tester.enterText(find.byKey(const Key('tag-search')), 'Alpha');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create \u201cAlpha\u201d'));
      await tester.pumpAndSettle();

      // In the list, A to Z (Alpha before Bravo), already ticked.
      expect(tester.getTopLeft(find.text('Alpha')).dy,
          lessThan(tester.getTopLeft(find.text('Bravo')).dy));
      expect(find.text('1 selected'), findsOneWidget);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      expect(result, {'new-Alpha'});
    });

    testWidgets('there is no "Add tag" button, with or without creating',
        (tester) async {
      await open(tester, options: _tags(3));
      expect(find.text('Add tag'), findsNothing);
      expect(find.byTooltip('Add tag'), findsNothing);
    });

    testWidgets('where tags can be created, the dialog has no "Add tag" either',
        (tester) async {
      await open(tester,
          options: _tags(3), onCreate: (n) async => TagOption(n, n));
      expect(find.text('Add tag'), findsNothing);
      expect(find.byKey(const Key('tag-add-input')), findsNothing);
    });

    testWidgets('the search hint says tags can be created, only where they can',
        (tester) async {
      await open(tester,
          options: _tags(3), onCreate: (n) async => TagOption(n, n));
      expect(find.text('Search or create a tag'), findsOneWidget);
    });

    testWidgets('where they cannot, the hint is plain search', (tester) async {
      await open(tester, options: _tags(3));
      expect(find.text('Search tags'), findsOneWidget);
      expect(find.text('Search or create a tag'), findsNothing);
    });

    testWidgets('no tags at all says so', (tester) async {
      await open(tester, options: const []);
      expect(find.text('No tags yet'), findsOneWidget);
    });

    testWidgets('no tags yet, where they can be created, says how',
        (tester) async {
      await open(tester,
          options: const [], onCreate: (n) async => TagOption(n, n));
      expect(find.text('No tags yet. Type a name above to create one.'),
          findsOneWidget);
    });

  });

  group('TagPickerDialog search and polish', () {
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

    const fruit = [
      TagOption('a', 'Apple'),
      TagOption('b', 'Banana'),
      TagOption('bl', 'Blueberry'),
      TagOption('c', 'Cherry'),
    ];

    Future<void> search(WidgetTester tester, String text) async {
      await tester.enterText(find.byKey(const Key('tag-search')), text);
      await tester.pumpAndSettle();
    }

    testWidgets('searching narrows the list, ignoring case', (tester) async {
      await open(tester, options: fruit);

      await search(tester, 'BLUE');

      expect(find.text('Blueberry'), findsOneWidget);
      expect(find.text('Apple'), findsNothing);
      expect(find.text('Banana'), findsNothing);
      expect(find.text('Cherry'), findsNothing);
    });

    testWidgets('it matches anywhere in the name', (tester) async {
      await open(tester, options: fruit);
      await search(tester, 'err');
      expect(find.text('Cherry'), findsOneWidget);
      expect(find.text('Blueberry'), findsOneWidget);
      expect(find.text('Apple'), findsNothing);
    });

    testWidgets('clearing the search brings every tag back', (tester) async {
      await open(tester, options: fruit);
      await search(tester, 'zzz');
      expect(find.text('Apple'), findsNothing);

      await tester.tap(find.byTooltip('Clear search'));
      await tester.pumpAndSettle();

      for (final f in ['Apple', 'Banana', 'Blueberry', 'Cherry']) {
        expect(find.text(f), findsOneWidget);
      }
    });

    testWidgets('no match says so, naming what was searched for',
        (tester) async {
      await open(tester, options: fruit);
      await search(tester, 'zzz');
      expect(find.text('No tags match \u201czzz\u201d'), findsOneWidget);
    });

    testWidgets('with nothing to create, a no-match search offers no "Create"',
        (tester) async {
      await open(tester, options: fruit);
      await search(tester, 'zzz');
      expect(find.textContaining('Create'), findsNothing);
    });

    testWidgets('a search for a new name offers to create it', (tester) async {
      Set<String>? result;
      await open(
        tester,
        options: fruit,
        onCreate: (name) async => TagOption('new-$name', name),
        onResult: (r) => result = r,
      );

      await search(tester, 'Mango');
      expect(find.text('Create \u201cMango\u201d'), findsOneWidget);

      await tester.tap(find.text('Create \u201cMango\u201d'));
      await tester.pumpAndSettle();

      // Created, ticked, and the search is cleared so it shows in the full list.
      expect(find.text('Mango'), findsOneWidget);
      expect(find.text('Apple'), findsOneWidget);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(result, {'new-Mango'});
    });

    testWidgets('an exact match is not offered as a new tag', (tester) async {
      await open(tester,
          options: fruit, onCreate: (name) async => TagOption(name, name));
      await search(tester, 'banana');
      expect(find.textContaining('Create'), findsNothing);
      expect(find.text('Banana'), findsOneWidget);
    });

    testWidgets('ticks survive searching', (tester) async {
      Set<String>? result;
      await open(tester, options: fruit, onResult: (r) => result = r);

      await tester.tap(find.text('Apple'));
      await search(tester, 'cher');
      await tester.tap(find.text('Cherry'));
      await tester.tap(find.byTooltip('Clear search'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      expect(result, {'a', 'c'});
    });

    testWidgets('the header counts what is ticked, live', (tester) async {
      await open(tester, options: fruit, selected: const {'b'});
      expect(find.text('1 selected'), findsOneWidget);

      await tester.tap(find.text('Apple'));
      await tester.pump();
      expect(find.text('2 selected'), findsOneWidget);

      await tester.tap(find.text('Apple'));
      await tester.tap(find.text('Banana'));
      await tester.pump();
      expect(find.text('None selected'), findsOneWidget);
    });

    testWidgets('letter headings group the list, and go while searching',
        (tester) async {
      await open(tester, options: fruit);
      expect(find.text('A'), findsOneWidget);
      expect(find.text('B'), findsOneWidget);
      expect(find.text('C'), findsOneWidget);

      await search(tester, 'b');
      expect(find.text('A'), findsNothing);
      expect(find.text('B'), findsNothing);
    });

    testWidgets('the close button in the header dismisses it', (tester) async {
      var called = false;
      Set<String>? result = {'unset'};
      await open(tester, options: fruit, onResult: (r) {
        called = true;
        result = r;
      });

      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();

      expect(called, isTrue);
      expect(result, isNull);
    });
  });

  group('TagPickerDialog layout', () {
    Future<void> openWith(
      WidgetTester tester, {
      required ThemeData theme,
      required Size size,
      required double textScale,
      required List<TagOption> options,
    }) async {
      tester.view.physicalSize = size * 3;
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        theme: theme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => TagPickerDialog.show(
                context,
                options: options,
                selected: const {'t3'},
                onCreate: (name) async => TagOption(name, name),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    final longNames = [
      for (var i = 0; i < 40; i++)
        TagOption('t$i',
            'A very long tag name number $i that has to be cut with an ellipsis'),
    ];

    for (final entry in {
      'light': AppTheme.light(),
      'dark': AppTheme.dark(),
    }.entries) {
      testWidgets(
          'a narrow screen, 200% text and long names lay out in the '
          '${entry.key} theme without overflow', (tester) async {
        await openWith(tester,
            theme: entry.value,
            size: const Size(320, 640),
            textScale: 2.0,
            options: longNames);

        expect(tester.takeException(), isNull);
        expect(find.byKey(const Key('tag-search')), findsOneWidget);
        expect(find.text('Done'), findsOneWidget);

        // Scrolling and searching still work at that size.
        await tester.drag(find.byType(ListView), const Offset(0, -600));
        await tester.pumpAndSettle();
        await tester.enterText(find.byKey(const Key('tag-search')), 'number 7');
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('with the keyboard up the dialog still fits the screen',
        (tester) async {
      tester.view.viewInsets = const FakeViewPadding(bottom: 300 * 3);
      addTearDown(tester.view.resetViewInsets);
      await openWith(tester,
          theme: AppTheme.light(),
          size: const Size(360, 640),
          textScale: 1.0,
          options: longNames);

      await tester.tap(find.byKey(const Key('tag-search')));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      // The footer is the lowest thing in the card: it must clear the keyboard.
      expect(tester.getRect(find.text('Done')).bottom,
          lessThanOrEqualTo(640 - 300 + 1),
          reason: 'the dialog must sit above the keyboard');
    });
  });
}
