// Pins what the render matrix cannot: that a modal sheet stays clear of a
// notch at the top and a gesture bar at the bottom.
//
// showModalBottomSheet defaults useSafeArea to false, and in that mode it
// also calls MediaQuery.removePadding(removeTop: true) — so a SafeArea inside
// the sheet has no effect at the top either. Both halves are easy to get
// wrong and invisible in review, which is why they are asserted here.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _topInset = 59.0;
const _bottomInset = 34.0;

/// Opens a sheet under a simulated cutout and returns the sheet's own rect.
Future<Rect> _sheetRect(
  WidgetTester tester, {
  required bool useSafeArea,
  bool safeAreaInBody = false,
}) async {
  final key = GlobalKey();

  // The sheet is a route on the Navigator, which sits *above* anything home
  // wraps — so a MediaQuery inside home never reaches it. The insets have to
  // come from the view itself, exactly as they do on a real device.
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(400, 800);
  tester.view.padding =
      const FakeViewPadding(top: _topInset, bottom: _bottomInset);
  tester.view.viewPadding =
      const FakeViewPadding(top: _topInset, bottom: _bottomInset);
  addTearDown(tester.view.reset);

  await tester.pumpWidget(MaterialApp(
    home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                useSafeArea: useSafeArea,
                isScrollControlled: true,
                builder: (_) {
                  final body = SizedBox(
                    key: safeAreaInBody ? null : key,
                    height: 2000, // taller than the window: wants every pixel
                    child: const Text('sheet'),
                  );
                  return safeAreaInBody
                      ? SafeArea(
                          top: false,
                          child: SizedBox(key: key, child: body),
                        )
                      : body;
                },
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
  ));

  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return tester.getRect(find.byKey(key));
}

void main() {
  testWidgets('without useSafeArea a tall sheet runs under the notch',
      (tester) async {
    final rect = await _sheetRect(tester, useSafeArea: false);
    // This is the bug the audit found: the sheet starts at the very top of
    // the window, behind the Dynamic Island.
    expect(rect.top, lessThan(_topInset),
        reason: 'sheet should have been allowed under the cutout here');
  });

  testWidgets('useSafeArea keeps the sheet below the notch', (tester) async {
    final rect = await _sheetRect(tester, useSafeArea: true);
    expect(rect.top, greaterThanOrEqualTo(_topInset),
        reason: 'useSafeArea: true must clear the top inset');
  });

  testWidgets('useSafeArea alone does not clear the gesture bar',
      (tester) async {
    final rect = await _sheetRect(tester, useSafeArea: true);
    final windowHeight = tester.view.physicalSize.height /
        tester.view.devicePixelRatio;
    // Flutter wraps in SafeArea(bottom: false), so the sheet still extends
    // to the bottom edge. This is why the sheet bodies also carry a
    // SafeArea(top: false) — remove that and this expectation is what breaks.
    expect(rect.bottom, closeTo(windowHeight, 1.0));
  });

  testWidgets('a SafeArea(top: false) in the body clears the gesture bar',
      (tester) async {
    final rect =
        await _sheetRect(tester, useSafeArea: true, safeAreaInBody: true);
    final windowHeight = tester.view.physicalSize.height /
        tester.view.devicePixelRatio;
    expect(rect.bottom, lessThanOrEqualTo(windowHeight - _bottomInset + 1));
  });
}
