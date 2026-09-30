// The book list in the reference picker has to be reachable to its end.
//
// It was laid out in full inside an Expanded + ClipRect with
// NeverScrollableScrollPhysics, so the sixty-six books were measured, painted
// as far as the dialog's height allowed, and the rest clipped. The end of the
// New Testament — Jude, Revelation — was in the widget tree and off the glass,
// with no scrollbar or cut-off row to suggest it existed. Reported from the
// note editor, where this picker inserts a verse.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:notify/core/theme/app_theme.dart';
import 'package:notify/features/bible/domain/models/bible_books.dart';
import 'package:notify/features/notes/presentation/widgets/editor/bible_reference_picker.dart';
import 'package:notify/l10n/l10n.dart';

/// Small enough that sixty-six chips cannot fit the dialog, which takes 70% of
/// this height. The precondition assertion below fails rather than the test
/// passing quietly if that ever stops being true.
const _shortScreen = Size(800, 1400);

/// Opens the book picker.
///
/// [onPicked] fires when the dialog returns, which is after the caller's own
/// awaits — so a helper that returned the selection directly would always hand
/// back null, the dialog still being open at that point.
Future<void> _openPicker(
  WidgetTester tester, {
  void Function(BibleBook?)? onPicked,
}) async {
  tester.view.physicalSize = _shortScreen;
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  final book =
                      await BibleReferencePicker.showBookPicker(context);
                  onPicked?.call(book);
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the last book starts out of reach and can be scrolled to', (
    tester,
  ) async {
    await _openPicker(tester);

    final revelation = find.widgetWithText(FilterChip, 'Rev');
    expect(revelation, findsOneWidget,
        reason: 'the chip is laid out even when it cannot be reached');

    // Precondition: it starts below the fold. Without this the test would pass
    // on a screen tall enough to show everything, proving nothing.
    final viewportBottom =
        tester.getRect(find.byType(SingleChildScrollView)).bottom;
    expect(tester.getRect(revelation).top, greaterThan(viewportBottom),
        reason: 'Revelation should start off-screen at this height — if it '
            'does not, the dialog now fits all 66 books and this test is '
            'no longer testing scrolling');

    await tester.drag(
        find.byType(SingleChildScrollView), const Offset(0, -600));
    await tester.pumpAndSettle();

    expect(tester.getRect(revelation).bottom, lessThanOrEqualTo(viewportBottom),
        reason: 'dragging must bring the end of the New Testament into view');
  });

  testWidgets('and choosing it there returns Revelation', (tester) async {
    BibleBook? picked;
    await _openPicker(tester, onPicked: (b) => picked = b);

    await tester.drag(
        find.byType(SingleChildScrollView), const Offset(0, -600));
    await tester.pumpAndSettle();

    // warnIfMissed stays on deliberately: a tap that lands outside the clip is
    // exactly the failure being tested, and it should be loud.
    await tester.tap(find.widgetWithText(FilterChip, 'Rev'));
    await tester.pumpAndSettle();

    // The book itself, not merely that the dialog closed — a barrier tap or a
    // pop with no result would satisfy the weaker assertion.
    expect(picked, isNotNull, reason: 'the picker must return a selection');
    expect(picked!.name, 'Revelation');
  });

  testWidgets('the scrollbar tells the user the list continues', (tester) async {
    await _openPicker(tester);

    // The other half of the report: with the list ending flush at the clip
    // there was nothing to suggest more books existed.
    expect(find.byType(Scrollbar), findsOneWidget);
  });
}
