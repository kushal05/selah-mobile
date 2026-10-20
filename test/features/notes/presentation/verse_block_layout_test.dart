// A Bible verse in a note runs the card's full width, a step below the note's
// own text size.
//
// The verse sat in the middle column of the reference row, between the book
// icon and the edit/remove/chevron icons, which left it a narrow strip down
// the centre of the card; and at 16pt it matched the note's body, so a quoted
// verse read like more of the note.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:notify/core/theme/app_theme.dart';
import 'package:notify/features/bible/domain/models/bible_reference.dart';
import 'package:notify/features/notes/presentation/widgets/editor/bible_reference_block_widget.dart';
import 'package:notify/l10n/l10n.dart';

const _v16 = 'For God so loved the world, that he gave his only begotten Son.';
const _v17 = 'For God sent not his Son into the world to condemn the world.';

BibleReference _ref(List<BibleVerseText> text) => BibleReference(
      reference: BibleVerseReference(
          book: 'John', chapter: 3, verses: [for (final t in text) t.verse],
          version: 'KJV'),
      text: text,
    );

Future<void> _pump(WidgetTester tester, BibleReference reference,
    {VoidCallback? onEdit,
    VoidCallback? onRemove,
    List<String> translations = const [],
    Size size = const Size(390, 800)}) async {
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    child: MaterialApp(
      theme: AppTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: BibleReferenceBlockWidget(
            reference: reference,
            onEdit: onEdit ?? () {},
            onRemove: onRemove ?? () {},
            onChangeVersion: (_) {},
            availableTranslations: translations,
          ),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

/// The rendered verse paragraph: the italic Text under the reference.
Finder _verse(String containing) => find.byWidgetPredicate((w) =>
    (w is Text && (w.data?.contains(containing) ?? false)) ||
    (w is RichText && w.text.toPlainText().contains(containing)));

void main() {
  testWidgets('the verse runs the full width, under the icons as well',
      (tester) async {
    await _pump(tester, _ref([const BibleVerseText(verse: 16, content: _v16)]));
    final verse = tester.getRect(_verse('so loved').first);
    final book = tester.getRect(find.byIcon(Icons.menu_book));
    final edit = tester.getRect(find.byIcon(Icons.edit_outlined));
    final reference = tester.getRect(find.text('John 3:16 (KJV)'));

    expect(verse.left, closeTo(book.left - 7, 8),
        reason: 'starts at the card edge, under the book icon, not beside it');
    expect(verse.right, greaterThan(edit.left),
        reason: 'runs on under the edit and remove icons');
    expect(verse.top, greaterThanOrEqualTo(reference.bottom),
        reason: 'below the reference row');
  });

  testWidgets('the verse is set at 14pt', (tester) async {
    await _pump(tester, _ref([const BibleVerseText(verse: 16, content: _v16)]));
    final text = tester.widget<Text>(find.text(_v16));
    expect(text.style!.fontSize, 14);
  });

  testWidgets('with verse numbers, 14pt text and 11pt numbers', (tester) async {
    await _pump(
        tester,
        _ref(const [
          BibleVerseText(verse: 16, content: _v16),
          BibleVerseText(verse: 17, content: _v17),
        ]));
    final rich = tester.widget<Text>(find.byWidgetPredicate(
        (w) => w is Text && w.textSpan != null &&
            w.textSpan!.toPlainText().contains('so loved')));
    final span = rich.textSpan! as TextSpan;
    expect(span.style!.fontSize, 14);
    final number = (span.children!.first as TextSpan).children!.first as TextSpan;
    expect(number.text, '16 ');
    expect(number.style!.fontSize, 11);
  });

  testWidgets('edit and ⋮ each answer a 44pt touch, not just the glyph',
      (tester) async {
    // Drawn at 16pt with 4pt of padding, the row's icons were 24pt targets
    // side by side.
    final taps = <String>[];
    await _pump(tester, _ref([const BibleVerseText(verse: 16, content: _v16)]),
        onEdit: () => taps.add('edit'));
    final edit = tester.getCenter(find.byIcon(Icons.edit_outlined));
    final more = tester.getCenter(find.byIcon(Icons.more_vert_rounded));
    expect((more - edit).dx, greaterThanOrEqualTo(44),
        reason: 'side by side, their targets must not overlap');

    // 18pt above and below the glyph: well outside the old 24pt target,
    // inside a 44pt one.
    await tester.tapAt(edit + const Offset(0, -18));
    await tester.tapAt(edit + const Offset(0, 18));
    await tester.pump();
    expect(taps, ['edit', 'edit']);

    await tester.tapAt(more + const Offset(0, 18));
    await tester.pumpAndSettle();
    expect(find.text('Copy verse text'), findsOneWidget,
        reason: 'the ⋮ opens the card\'s menu');
  });

  testWidgets('the menu holds what left the row: tag, version, remove, copy',
      (tester) async {
    await _pump(tester, _ref([const BibleVerseText(verse: 16, content: _v16)]));
    expect(find.byIcon(Icons.close), findsNothing,
        reason: 'remove is in the menu now, not beside edit');
    await tester.tap(find.byIcon(Icons.more_vert_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Remove reference'), findsOneWidget);
    expect(find.text('Edit reference'), findsOneWidget);
    expect(find.text('Copy reference'), findsOneWidget);
  });

  testWidgets('the reference gets the width to sit on one line',
      (tester) async {
    // Tag, edit and remove with full touch areas left the reference about
    // 130pt, and "John 3:16-17 (KJV)" — about 150pt in the app's font — wrapped
    // onto two lines. Measured as the width the reference is given, because
    // the test font draws every glyph a full em wide and wraps it regardless.
    await _pump(
        tester,
        _ref(const [
          BibleVerseText(verse: 16, content: _v16),
          BibleVerseText(verse: 17, content: _v17),
        ]));
    expect(tester.getSize(find.text('John 3:16-17 (KJV)')).width,
        greaterThanOrEqualTo(165));
  });

  testWidgets('Change version is not offered with only one version',
      (tester) async {
    await _pump(tester, _ref([const BibleVerseText(verse: 16, content: _v16)]),
        translations: const ['KJV']);
    await tester.tap(find.byIcon(Icons.more_vert_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Change version'), findsNothing,
        reason: 'with one version installed the picker would show nothing');
  });

  testWidgets('but is, with another version to change to', (tester) async {
    await _pump(tester, _ref([const BibleVerseText(verse: 16, content: _v16)]),
        translations: const ['KJV', 'NKJV']);
    await tester.tap(find.byIcon(Icons.more_vert_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Change version'), findsOneWidget);
  });

  testWidgets('the menu scrolls rather than overflowing on a small screen',
      (tester) async {
    // Held to 9/16 of the screen, six actions ran out of room on a short
    // phone, and more so with larger text.
    await _pump(tester, _ref([const BibleVerseText(verse: 16, content: _v16)]),
        translations: const ['KJV', 'NKJV'], size: const Size(320, 480));
    await tester.tap(find.byIcon(Icons.more_vert_rounded));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(find.text('Remove reference'), 40,
        scrollable: find.byType(Scrollable).last);
    expect(find.text('Remove reference').hitTestable(), findsOneWidget);
  });

  testWidgets('a screen reader hears each button named once', (tester) async {
    // The tooltip carried the same words as the label, and both were read.
    final handle = tester.ensureSemantics();
    await _pump(tester, _ref([const BibleVerseText(verse: 16, content: _v16)]));
    for (final (icon, name) in [
      (Icons.edit_outlined, 'Edit reference'),
      (Icons.more_vert_rounded, 'More actions for John 3:16 (KJV)'),
    ]) {
      final node = tester.getSemantics(find.byIcon(icon));
      expect(node.label, name);
      expect(node.tooltip, isEmpty, reason: 'not "$name" a second time');
      expect(node.flagsCollection.isButton, isTrue);
    }
    handle.dispose();
  });
}
