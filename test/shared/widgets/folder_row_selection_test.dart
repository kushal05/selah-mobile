// A selected folder has to look selected, in whichever theme you are in.
//
// The row was filled with Colors.grey.shade100 — a fixed light grey. Against
// the dark theme's ground it was a near-white band across the list, which is
// what got reported. Measuring it showed the light theme was no better in the
// other direction: #F5F5F5 on a #F4F5F7 ground is a difference of two points,
// so selection was all but invisible there too.
//
// A tint of the folder's own accent composites over whichever ground is behind
// it, so it lands correctly in both and says "selected" rather than merely
// "different".

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:notify/core/theme/app_theme.dart';
import 'package:notify/core/theme/theme_colors.dart';
import 'package:notify/shared/widgets/lists/folder_row.dart';

double _lin(double c) =>
    c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();

double _luminance(Color c) =>
    0.2126 * _lin((c.r * 255).roundToDouble() / 255) +
    0.7152 * _lin((c.g * 255).roundToDouble() / 255) +
    0.0722 * _lin((c.b * 255).roundToDouble() / 255);

double _ratio(Color a, Color b) {
  final la = _luminance(a), lb = _luminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// sRGB to CIE L*a*b* under D65 — the space a perceptual difference is defined
/// in. Needed because contrast ratio is a luminance measure and says almost
/// nothing about a change of hue: an 8% tint of the accent shifts colour far
/// more than it shifts brightness, so a ratio near 1.0 understates how visible
/// it is, and a gate built on the ratio alone has to be set so low that it
/// stops meaning anything.
(double, double, double) _lab(Color c) {
  double lin(double v) =>
      v <= 0.04045 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  final r = lin(c.r), g = lin(c.g), b = lin(c.b);
  final x = (0.4124 * r + 0.3576 * g + 0.1805 * b) / 0.95047;
  final y = 0.2126 * r + 0.7152 * g + 0.0722 * b;
  final z = (0.0193 * r + 0.1192 * g + 0.9505 * b) / 1.08883;
  double f(double t) =>
      t > 0.008856 ? math.pow(t, 1 / 3).toDouble() : (7.787 * t) + 16 / 116;
  final fx = f(x), fy = f(y), fz = f(z);
  return (116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz));
}

/// CIE76 colour difference. Roughly: below 2.3 two colours are the same to the
/// eye, and the number grows with how plainly they differ.
double _deltaE(Color a, Color b) {
  final (l1, a1, b1) = _lab(a);
  final (l2, a2, b2) = _lab(b);
  return math.sqrt(
      math.pow(l1 - l2, 2) + math.pow(a1 - a2, 2) + math.pow(b1 - b2, 2));
}

/// Reliably noticeable. The just-noticeable difference is about 2.3; this asks
/// for a little more so a tint is seen rather than suspected.
const _noticeable = 3.0;

/// Still a tint and not a second surface. Every accent currently lands between
/// 5 and 11, so this leaves plenty of room — it is here to catch the regression
/// that was actually reported, a fixed light grey that measured 91 against the
/// dark ground.
const _quiet = 25.0;

/// The colour the selected row actually paints, composited over the ground it
/// sits on — the fill carries alpha, so the raw value says little on its own.
Future<(Color fill, Color ground, Color ink)> _selected(
  WidgetTester tester,
  ThemeData theme, {
  Color? accent,
}) async {
  late BuildContext captured;
  await tester.pumpWidget(MaterialApp(
    theme: theme,
    home: Scaffold(
      body: Builder(builder: (context) {
        captured = context;
        return FolderRow(
          title: 'Sermons',
          noteCount: 3,
          isActive: true,
          accentColor: accent,
        );
      }),
    ),
  ));
  await tester.pump();

  final material = tester.widget<Material>(
    find.ancestor(of: find.text('Sermons'), matching: find.byType(Material)).first,
  );
  final ground = theme.scaffoldBackgroundColor;
  return (
    Color.alphaBlend(material.color ?? Colors.transparent, ground),
    ground,
    captured.primaryText,
  );
}

void main() {
  testWidgets('the selected fill is not the same colour in both themes',
      (tester) async {
    final (light, _, _) = await _selected(tester, AppTheme.light());
    final (dark, _, _) = await _selected(tester, AppTheme.dark());

    expect(light, isNot(dark),
        reason: 'a fixed literal would paint the same band in both, which is '
            'how a near-white row ended up on the dark ground');
  });

  // Both accents a caller actually passes: notes leaves it at the brandPurple
  // default, songs passes orange. Only purple was measured before, and orange
  // is the weaker of the two.
  const accents = {'purple (notes)': null, 'orange (songs)': AppTheme.orange};

  for (final theme in {'light': AppTheme.light(), 'dark': AppTheme.dark()}.entries) {
    for (final accent in accents.entries) {
      testWidgets(
          'a ${accent.key} selection is noticeable but quiet, on ${theme.key}',
          (tester) async {
        // This gate replaced `contrast ratio > 1.03`, which was near enough to
        // vacuous: the light-theme orange tint measures 1.05 and passed with
        // almost nothing to spare, so a tint that had lost its colour entirely
        // would still have got through. A perceptual difference catches both
        // ways of getting this wrong, and both have happened here — the grey
        // literal measured 1.08 against the light ground, invisible, and 91.13
        // against the dark one, which is the near-white band that was reported.
        final (fill, ground, _) =
            await _selected(tester, theme.value, accent: accent.value);
        final de = _deltaE(fill, ground);

        expect(de, greaterThan(_noticeable),
            reason: 'the selected row must be tellable from the page behind it');
        expect(de, lessThan(_quiet),
            reason: 'a selection tint is a tint, not a second surface');
      });

      testWidgets('and its ${accent.key} label still reads, on ${theme.key}',
          (tester) async {
        final (fill, _, ink) =
            await _selected(tester, theme.value, accent: accent.value);

        expect(_ratio(ink, fill), greaterThanOrEqualTo(4.5),
            reason: 'selection must not cost legibility');
      });
    }
  }
}
