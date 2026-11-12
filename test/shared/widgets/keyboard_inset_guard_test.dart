// A keyboard inset that outlives the keyboard (after the app was left with the
// keyboard open) must not shrink the screen; a real keyboard must still lift
// the field it belongs to.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:notify/shared/widgets/keyboard_inset_guard.dart';

Widget _app({required double inset, FocusNode? focus}) => MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(viewInsets: EdgeInsets.only(bottom: inset)),
        child: KeyboardInsetGuard(child: child!),
      ),
      home: Scaffold(
        body: Column(
          children: [
            const Expanded(child: SizedBox(key: Key('page'))),
            TextField(focusNode: focus),
          ],
        ),
      ),
    );

void main() {
  testWidgets('with no field focused, a stale keyboard inset is ignored',
      (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(inset: 300));
    await tester.pump();

    expect(tester.getSize(find.byKey(const Key('page'))).height,
        greaterThan(600),
        reason: 'the page keeps the whole screen, not the half left by 300');
  });

  testWidgets('with a field focused, the keyboard inset still applies',
      (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final focus = FocusNode();
    addTearDown(focus.dispose);

    await tester.pumpWidget(_app(inset: 300, focus: focus));
    focus.requestFocus();
    await tester.pump();
    await tester.pump();

    expect(tester.getSize(find.byKey(const Key('page'))).height,
        lessThan(500), reason: 'room is made for the real keyboard');
  });

  testWidgets('the inset is dropped again when focus leaves the field',
      (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final focus = FocusNode();
    addTearDown(focus.dispose);

    await tester.pumpWidget(_app(inset: 300, focus: focus));
    focus.requestFocus();
    await tester.pump();
    focus.unfocus();
    await tester.pump();
    await tester.pump();

    expect(tester.getSize(find.byKey(const Key('page'))).height,
        greaterThan(600));
  });

  testWidgets('no keyboard, nothing changes', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(inset: 0));
    await tester.pump();

    expect(tester.getSize(find.byKey(const Key('page'))).height,
        greaterThan(600));
  });
}
