// The app must let text reach 200%.
//
// WCAG 1.4.4 requires text to scale to 200% without loss of content, so 2.0 is
// the floor for the ceiling the app applies. An earlier clamp of 1.6 sat below
// that and failed the criterion outright, which is the regression worth holding
// against: the risk is not that the clamp disappears but that someone tightens
// it to stop a layout from overflowing.
//
// Asserted against the source because the clamp lives inside MaterialApp's
// anonymous `builder`, which cannot be reached without booting the whole app —
// auth, sync, notifications and all. Mutation testing is what surfaced the need:
// removing the clamp entirely left every gate green, `flutter analyze` included
// once the symbol still resolved.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('text scaling is clamped no lower than 200%', () {
    // Comments stripped first, or commenting the clamp out would satisfy this —
    // which is exactly how the first version of this test passed a mutation
    // that had disabled the clamp.
    final src = File('lib/main.dart')
        .readAsLinesSync()
        .map((l) => l.replaceFirst(RegExp(r'\s*//.*$'), ''))
        .join('\n');

    expect(src.contains('MediaQuery.withClampedTextScaling('), isTrue,
        reason: 'the app must clamp text scaling rather than pass it through');

    final match =
        RegExp(r'maxScaleFactor:\s*([0-9]+(?:\.[0-9]+)?)').firstMatch(src);
    expect(match, isNotNull, reason: 'the clamp must state its ceiling');

    final ceiling = double.parse(match!.group(1)!);
    expect(ceiling, greaterThanOrEqualTo(2.0),
        reason: 'WCAG 1.4.4 needs 200%; $ceiling would fail the criterion');
  });
}
