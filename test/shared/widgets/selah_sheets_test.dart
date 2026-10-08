// The shared sheets that replace the app's AlertDialogs: confirm, input and
// list. Each is driven through a real showModalBottomSheet route, so the
// results asserted are what a caller's `await` actually receives.

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:notify/core/theme/app_theme.dart';
import 'package:notify/l10n/l10n.dart';
import 'package:notify/shared/widgets/sheets/sheets.dart';

double _contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  return (la > lb ? la + 0.05 : lb + 0.05) / (la > lb ? lb + 0.05 : la + 0.05);
}

/// Pumps an app whose one button runs [open]; returns a getter for whatever
/// [open]'s future completed with, and whether it has completed.
Future<({Object? Function() result, bool Function() done})> _pump(
  WidgetTester tester,
  Future<Object?> Function(BuildContext context) open, {
  ThemeData? theme,
  Size size = const Size(400, 800),
  double textScale = 1.0,
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);

  Object? result;
  var done = false;
  await tester.pumpWidget(MaterialApp(
    theme: theme ?? AppTheme.light(),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () async {
              result = await open(context);
              done = true;
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return (result: () => result, done: () => done);
}

Finder _primary(String label) => find.widgetWithText(FilledButton, label);

/// The tinted circle behind a header icon — the painted box, not the
/// Container, whose rect includes the margin that positions it.
Rect _badge(WidgetTester tester, IconData icon) => tester.getRect(find
    .ancestor(of: find.byIcon(icon), matching: find.byType(DecoratedBox))
    .first);

Future<void> _dismissByTapOutside(WidgetTester tester) async {
  await tester.tapAt(const Offset(200, 20));
  await tester.pumpAndSettle();
}

void main() {
  group('showConfirmSheet', () {
    Future<Object?> open(BuildContext c, {bool destructive = false}) =>
        showConfirmSheet(c,
            title: 'Delete note?',
            message: 'Moves to Trash for 30 days.',
            confirmLabel: 'Delete',
            icon: Icons.delete_outline,
            destructive: destructive);

    testWidgets('confirming returns true', (tester) async {
      final r = await _pump(tester, open);
      expect(find.text('Moves to Trash for 30 days.'), findsOneWidget);
      await tester.tap(_primary('Delete'));
      await tester.pumpAndSettle();
      expect(r.done(), isTrue);
      expect(r.result(), isTrue);
    });

    testWidgets('Cancel returns false', (tester) async {
      final r = await _pump(tester, open);
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();
      expect(r.done(), isTrue);
      expect(r.result(), isFalse);
    });

    testWidgets('dismissing returns false, not null', (tester) async {
      final r = await _pump(tester, open);
      await _dismissByTapOutside(tester);
      expect(r.done(), isTrue);
      expect(r.result(), isFalse);
    });

    for (final (name, theme) in [
      ('light', AppTheme.light()),
      ('dark', AppTheme.dark()),
    ]) {
      testWidgets('a destructive action is red and its label reads ($name)',
          (tester) async {
        await _pump(tester, (c) => open(c, destructive: true), theme: theme);
        final button = tester.widget<FilledButton>(_primary('Delete'));
        final fill = button.style!.backgroundColor!.resolve({})!;
        final label = button.style!.foregroundColor!.resolve({})!;
        expect(fill.r, greaterThan(fill.g * 2),
            reason: 'destructive fill is red: $fill');
        expect(_contrast(fill, label), greaterThanOrEqualTo(4.5));
      });
    }

    testWidgets('a title that wraps at normal size lines up at the top',
        (tester) async {
      const long = 'Delete "Prayers for the family reunion" and its notes?';
      await _pump(
          tester,
          (c) => showConfirmSheet(c,
              title: long, confirmLabel: 'Delete', icon: Icons.delete_outline));
      final title = tester.getRect(find.text(long));
      final badge = _badge(tester, Icons.delete_outline);
      expect(title.height, greaterThan(badge.height),
          reason: 'precondition: the title wraps past the badge');
      expect(badge.top, title.top);
    });

    testWidgets('a one-line title sits centred beside its icon',
        (tester) async {
      await _pump(tester, open);
      final title = tester.getRect(find.text('Delete note?'));
      expect(_badge(tester, Icons.delete_outline).center.dy,
          closeTo(title.center.dy, 0.5));
    });

    testWidgets('both buttons paint at least 48pt tall', (tester) async {
      await _pump(tester, open);
      // The painted surface, not the button: Material pads every button's
      // hit area to 48 whatever it draws, which would hide a squat button.
      double painted(Finder button) => tester
          .getSize(find.descendant(of: button, matching: find.byType(Material)))
          .height;
      expect(painted(_primary('Delete')), greaterThanOrEqualTo(48));
      expect(painted(find.widgetWithText(TextButton, 'Cancel')),
          greaterThanOrEqualTo(48));
    });
  });

  group('AppTheme.filledFor', () {
    test('every label it returns reads on its fill', () {
      for (final accent in [
        AppTheme.brandBlue,
        AppTheme.orange,
        AppTheme.errorSurface,
        AppTheme.brandPurple, // white on it is 4.20: needs the darker fill
      ]) {
        final f = AppTheme.filledFor(accent);
        expect(_contrast(f.fill, f.label), greaterThanOrEqualTo(4.5),
            reason: 'accent $accent');
      }
    });

    test('keeps an accent that already works', () {
      expect(AppTheme.filledFor(AppTheme.brandBlue).fill, AppTheme.brandBlue);
    });

    test('darkens one that does not', () {
      expect(AppTheme.filledFor(AppTheme.brandPurple).fill,
          isNot(AppTheme.brandPurple));
    });

    test('refuses a colour it has no darker fill for, rather than going blue',
        () {
      // Mid-grey: white on it is 4.12, dark ink 4.13, and it is no accent.
      expect(() => AppTheme.filledFor(const Color(0xFF7D7D7D)),
          throwsAssertionError);
    });
  });

  group('showInputSheet', () {
    Future<Object?> open(BuildContext c,
            {String initial = '', String? Function(String)? validator}) =>
        showInputSheet(c,
            title: 'Rename folder',
            confirmLabel: 'Save',
            initialValue: initial,
            validator: validator);

    bool enabled(WidgetTester t) =>
        t.widget<FilledButton>(_primary('Save')).onPressed != null;

    testWidgets('the field has focus as the sheet opens', (tester) async {
      await _pump(tester, open);
      final field = tester.widget<EditableText>(find.byType(EditableText));
      expect(field.focusNode.hasFocus, isTrue);
    });

    testWidgets('Save is disabled until there is text, then returns it trimmed',
        (tester) async {
      final r = await _pump(tester, open);
      expect(enabled(tester), isFalse);

      await tester.enterText(find.byType(TextField), '   ');
      await tester.pump();
      expect(enabled(tester), isFalse, reason: 'whitespace is not a name');

      await tester.enterText(find.byType(TextField), '  Psalms  ');
      await tester.pump();
      expect(enabled(tester), isTrue);
      await tester.tap(_primary('Save'));
      await tester.pumpAndSettle();
      expect(r.result(), 'Psalms');
    });

    testWidgets('the keyboard action submits a single-line field',
        (tester) async {
      final r = await _pump(tester, open);
      await tester.enterText(find.byType(TextField), 'Hymns');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(r.result(), 'Hymns');
    });

    testWidgets('starts with the old value selected, to type over',
        (tester) async {
      await _pump(tester, (c) => open(c, initial: 'Psalms'));
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, 'Psalms');
      expect(field.controller!.selection,
          const TextSelection(baseOffset: 0, extentOffset: 6));
      expect(enabled(tester), isTrue);
    });

    String? noDupes(String v) => v.isEmpty
        ? 'Required'
        : v == 'Psalms'
            ? 'Already exists'
            : null;

    testWidgets('an empty, untouched field is not scolded', (tester) async {
      await _pump(tester, (c) => open(c, validator: noDupes));
      expect(enabled(tester), isFalse);
      expect(find.text('Required'), findsNothing);

      // Typed, then cleared: now it has been touched.
      await tester.enterText(find.byType(TextField), 'P');
      await tester.enterText(find.byType(TextField), '');
      await tester.pump();
      expect(find.text('Required'), findsOneWidget);
    });

    testWidgets('a starting value that fails says why Save is off at once',
        (tester) async {
      await _pump(tester, (c) => open(c, initial: 'Psalms', validator: noDupes));
      expect(enabled(tester), isFalse);
      expect(find.text('Already exists'), findsOneWidget);
    });

    testWidgets('a validator blocks Save, and the keyboard cannot get past it',
        (tester) async {
      final r = await _pump(tester, (c) => open(c, validator: noDupes));
      await tester.enterText(find.byType(TextField), 'Psalms');
      await tester.pump();
      expect(find.text('Already exists'), findsOneWidget);
      expect(enabled(tester), isFalse);

      // The keyboard's done must not slip past a disabled button.
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(r.done(), isFalse);
    });

    testWidgets('dismissing returns null', (tester) async {
      final r = await _pump(tester, open);
      await tester.enterText(find.byType(TextField), 'Unsaved');
      // The keyboard is not up in a test, so the barrier is reachable.
      await _dismissByTapOutside(tester);
      expect(r.done(), isTrue);
      expect(r.result(), isNull);
    });
  });

  group('showListSheet', () {
    final items = [
      for (var i = 0; i < 40; i++)
        SheetListItem(value: i, label: 'Folder $i', icon: Icons.folder),
    ];
    Future<Object?> open(BuildContext c) => showListSheet<int>(c,
        title: 'Move to folder', items: items, selected: 2);

    testWidgets('tapping a row returns its value', (tester) async {
      final r = await _pump(tester, open);
      await tester.tap(find.text('Folder 1'));
      await tester.pumpAndSettle();
      expect(r.result(), 1);
    });

    testWidgets('the current choice is checked and announced as selected',
        (tester) async {
      await _pump(tester, open);
      final row = find.ancestor(
          of: find.text('Folder 2'), matching: find.byType(InkWell));
      expect(
          find.descendant(of: row, matching: find.byIcon(Icons.check_rounded)),
          findsOneWidget);
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
      expect(tester.getSemantics(find.text('Folder 2')),
          matchesSemantics(
              label: 'Folder 2',
              isButton: true,
              hasSelectedState: true,
              isSelected: true,
              hasTapAction: true,
              hasFocusAction: true,
              isFocusable: true));
    });

    testWidgets('rows are at least 52pt tall', (tester) async {
      await _pump(tester, open);
      final row = find.ancestor(
          of: find.text('Folder 0'), matching: find.byType(InkWell));
      expect(tester.getSize(row).height, greaterThanOrEqualTo(52));
    });

    testWidgets('a long list scrolls inside 85% of the screen, header fixed',
        (tester) async {
      await _pump(tester, open);
      final sheet = tester.getRect(find.byType(SelahSheet));
      expect(sheet.height, lessThanOrEqualTo(800 * 0.85 + 0.5));
      final titleTop = tester.getTopLeft(find.text('Move to folder')).dy;

      await tester.scrollUntilVisible(find.text('Folder 39'), 300,
          scrollable: find.byType(Scrollable).last);
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.text('Move to folder')).dy, titleTop);
      await tester.tap(find.text('Folder 39'));
      await tester.pumpAndSettle();
    });
  });

  group('the action buttons', () {
    Future<Object?> open(BuildContext c, {String label = 'Log prayer'}) =>
        showConfirmSheet(c, title: 'Log this prayer?', confirmLabel: label);
    final cancel = find.widgetWithText(TextButton, 'Cancel');
    bool truncated(WidgetTester t, String label) =>
        t.renderObject<RenderParagraph>(find.text(label)).didExceedMaxLines;

    testWidgets('sit side by side, the main action twice as wide',
        (tester) async {
      await _pump(tester, open);
      final c = tester.getRect(cancel), p = tester.getRect(_primary('Log prayer'));
      expect(c.center.dy, p.center.dy);
      expect(c.right, lessThan(p.left), reason: 'Cancel on the left');
      expect(p.width, closeTo(c.width * 2, 1));
    });

    testWidgets('stack, main action on top, when the labels would be cut',
        (tester) async {
      // Test glyphs are a full em wide, so a label that fits the full width
      // here is shorter than it would be on a phone.
      await _pump(tester, (c) => open(c, label: 'Log it'),
          size: const Size(320, 640), textScale: 2.0);
      final c = tester.getRect(cancel), p = tester.getRect(_primary('Log it'));
      expect(p.bottom, lessThanOrEqualTo(c.top));
      expect(p.width, c.width);
      expect(truncated(tester, 'Cancel'), isFalse);
      expect(truncated(tester, 'Log it'), isFalse);

      // Still the buttons they were: each answers as before.
      await tester.tap(cancel);
      await tester.pumpAndSettle();
    });
  });

  group('measured by a parent', () {
    testWidgets('at the width it asks for, the buttons sit side by side',
        (tester) async {
      // IntrinsicWidth gives the sheet exactly the width it reports wanting.
      // That width came back, through floating point, a hair short of itself
      // for about one width in eleven, and the buttons stacked in it. Text
      // sizes in small steps make fractional widths, which find those cases.
      var checked = 0;
      for (var scale = 1.0; scale < 1.6; scale += 0.013) {
        await tester.pumpWidget(MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (c, child) => MediaQuery(
              data: MediaQuery.of(c)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!),
          home: const Material(
            child: Align(
              alignment: Alignment.topLeft,
              child: IntrinsicWidth(
                // A one-letter title, so the buttons set the width.
                child: SelahSheet(title: 'A', primaryLabel: 'Log it'),
              ),
            ),
          ),
        ));
        final cancel = tester.getRect(find.widgetWithText(TextButton, 'Cancel'));
        final primary = tester.getRect(_primary('Log it'));
        expect(cancel.center.dy, primary.center.dy,
            reason: 'stacked at text scale $scale');
        checked++;
      }
      expect(checked, greaterThan(40));
    });


    // Nothing measures the sheet today; these hold for the first parent that
    // does — an IntrinsicHeight, a dialog sizing to its content.
    Widget sheet() => MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Material(
            child: Align(
              alignment: Alignment.topCenter,
              child: IntrinsicHeight(
                child: SelahSheet(title: 'Delete note?', primaryLabel: 'Delete'),
              ),
            ),
          ),
        );

    testWidgets('reports the height the buttons really take', (tester) async {
      await tester.pumpWidget(sheet());
      expect(tester.takeException(), isNull);
      final button = tester.getRect(_primary('Delete'));
      final box = tester.getRect(find.byType(IntrinsicHeight));
      expect(button.height, greaterThanOrEqualTo(48));
      expect(button.bottom, lessThanOrEqualTo(box.bottom),
          reason: 'measured short, the buttons would hang out of the box');
    });

    testWidgets('dry layout agrees with real layout', (tester) async {
      for (final width in [360.0, 120.0]) {
        await tester.pumpWidget(sheet());
        final actions = tester.renderObject<RenderBox>(find
            .ancestor(of: _primary('Delete'), matching: find.byWidgetPredicate(
                (w) => w.runtimeType.toString() == '_ActionsLayout'))
            .first);
        final c = BoxConstraints(maxWidth: width);
        final dry = actions.getDryLayout(c);
        actions.layout(c, parentUsesSize: true);
        expect(dry, actions.size, reason: 'at $width');
        expect(actions.getMinIntrinsicHeight(width), actions.size.height);
      }
      expect(tester.takeException(), isNull);
    });
  });

  group('at 320pt wide with text at 200%', () {
    const small = Size(320, 640);

    testWidgets("the header icon is centred on the title's first line",
        (tester) async {
      const long = 'Delete "Prayers for the family reunion"?';
      await _pump(
          tester,
          (c) => showConfirmSheet(c,
              title: long, confirmLabel: 'Delete', icon: Icons.delete_outline),
          size: small,
          textScale: 2.0);
      final title = tester.getRect(find.text(long));
      final firstGlyph = tester
          .renderObject<RenderParagraph>(find.text(long))
          .getBoxesForSelection(
              const TextSelection(baseOffset: 0, extentOffset: 1))
          .first;
      final icon = _badge(tester, Icons.delete_outline);
      expect(title.height, greaterThan(firstGlyph.toRect().height * 2),
          reason: 'precondition: the title wraps');
      expect(icon.center.dy,
          closeTo(title.top + firstGlyph.toRect().center.dy, 0.5));
    });
    testWidgets('a confirm sheet lays out without overflow', (tester) async {
      await _pump(
          tester,
          (c) => showConfirmSheet(c,
              title: 'Delete "Prayers for the family reunion"?',
              message: 'Moves to Trash for 30 days, then is gone for good.',
              confirmLabel: 'Delete forever',
              icon: Icons.delete_outline,
              destructive: true),
          size: small,
          textScale: 2.0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('an input sheet lays out without overflow', (tester) async {
      await _pump(
          tester,
          (c) => showInputSheet(c,
              title: 'Rename folder',
              subtitle: 'Prayers for the family reunion',
              icon: Icons.edit,
              confirmLabel: 'Save',
              confirmIcon: Icons.check,
              validator: (v) => v == 'Psalms' ? 'Already exists' : null),
          size: small,
          textScale: 2.0);
      expect(tester.takeException(), isNull);

      await tester.enterText(find.byType(TextField), 'Psalms');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
          tester
              .renderObject<RenderParagraph>(find.text('Already exists'))
              .didExceedMaxLines,
          isFalse,
          reason: 'the whole reason is shown, not its first words');
    });

    testWidgets('a list sheet lays out without overflow', (tester) async {
      await _pump(
          tester,
          (c) => showListSheet<int>(c,
              title: 'Move to folder',
              subtitle: 'Prayers for the family reunion',
              icon: Icons.folder,
              items: [
                for (var i = 0; i < 12; i++)
                  SheetListItem(
                      value: i,
                      label: 'A long folder name number $i',
                      subtitle: '$i notes',
                      icon: Icons.folder),
              ]),
          size: small,
          textScale: 2.0);
      expect(tester.takeException(), isNull);
    });
  });
}
