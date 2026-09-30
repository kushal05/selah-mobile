// A heading belongs to the section under it, but not so tightly that it reads
// as part of the next heading.
//
// Every block in the editor was padded `bottom: 4`, whatever its type, so an H1
// sat sixteen pixels below the note's title and four above the H2 beneath it.
// The preview had the same imbalance from the other side: the title's own 16px
// gap stacked with the H1's `top: 16` to give thirty-two above and twenty
// below. Either way the H1 sat next to the H2 rather than between the title and
// the H2.
//
// This pins the rule rather than the pixel count. Measuring a miniature of the
// layout would certify a tree the app does not have, so the two things asserted
// are that the scale itself is ordered, and that both screens take their
// heading spacing from it instead of writing numbers in by hand.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:notify/core/theme/app_theme.dart';

const _editor =
    'lib/features/notes/presentation/screens/note_editor_screen.dart';
const _preview =
    'lib/features/notes/presentation/screens/note_detail_screen.dart';

void main() {
  test('the gap shrinks as the heading level descends', () {
    final gaps = [for (var l = 1; l <= 3; l++) AppTheme.noteHeadingGap(l)];
    expect(gaps, orderedEquals(<double>[...gaps]..sort((a, b) => b.compareTo(a))),
        reason: 'a deeper heading must not leave more air than a shallower one');
    // The paragraph default, which anything unrecognised falls back to. An H3
    // still has to out-space a plain block or the scale collapses at the bottom.
    expect(AppTheme.noteHeadingGap(3), greaterThan(AppTheme.noteHeadingGap(0)));
  });

  test('an H1 leaves roughly as much air as the note title leaves above it', () {
    // The title's gap is a fixed 16 in both screens, so this is the balance the
    // whole change is about: the H1 cannot leave a quarter of that and still
    // read as the thing the title hands over to.
    expect(AppTheme.noteHeadingGap(1), greaterThanOrEqualTo(12));
  });

  test('both screens derive heading spacing from the scale', () {
    for (final path in [_editor, _preview]) {
      final src = File(path).readAsStringSync();
      expect(src.contains('AppTheme.noteHeadingGap('), isTrue,
          reason: '$path must space headings through the shared scale');
    }
  });

  test('the preview does not stack its own 16 on top of the title gap', () {
    // The specific regression: `top: 16` on an H1, under a title that already
    // leaves 16 beneath itself, is the thirty-two-pixel gap that started this.
    final src = File(_preview).readAsStringSync();
    final h1 = src.indexOf('case BlockType.heading1:');
    expect(h1, isNot(-1), reason: 'the heading1 branch moved; update this test');
    final branch = src.substring(h1, src.indexOf('case BlockType.heading2:', h1));
    expect(branch.contains('top: 16'), isFalse,
        reason: 'the title already supplies 16 above an H1');
  });
}
