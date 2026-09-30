// What the chips actually paint, as opposed to what the palette promises.
//
// accent_ink_coverage_test measures `inkOnTintFor(accent)` against a tint of
// the **raw** accent. A selected FilterPill does not draw that: it fills with
// `semanticFor(accent).withValues(alpha: alphaLight)` — a tint of the *tuned*
// colour — and inks with `inkOnTintFor(accent)`. The two are different
// backgrounds, and this session moved the tuned one a long way for coral,
// amber and ministryPurple. At alpha 0.08 the difference turned out not to
// matter (the worst drawn pairing is teal at 6.72:1), but nothing measured the
// pairing that is painted, so nothing would notice if the alpha were raised.
//
// The last test is about a different hazard in the same area: `accentSurface`
// falls back to `brandBlueSurface` for any accent it has no entry for, which is
// eight of the fourteen. Today every SelectableChip passes an accent that is
// mapped, so nothing renders the wrong colour — this fails the day one does.

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:notify/core/theme/app_theme.dart';
import 'package:notify/core/theme/theme_colors.dart';

const _accents = <String, Color>{
  'brandBlue': AppTheme.brandBlue,
  'brandPurple': AppTheme.brandPurple,
  'teal': AppTheme.teal,
  'coral': AppTheme.coral,
  'emerald': AppTheme.emerald,
  'orange': AppTheme.orange,
  'amber': AppTheme.amber,
  'rosePink': AppTheme.rosePink,
  'ministryPurple': AppTheme.ministryPurple,
  'error': AppTheme.error,
  'warning': AppTheme.warning,
  'success': AppTheme.success,
  'info': AppTheme.info,
  'mutedGrey': AppTheme.mutedGrey,
};

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

/// [fg] composited over [bg] at [alpha], the way Flutter paints it.
Color _over(Color fg, double alpha, Color bg) => Color.lerp(bg, fg, alpha)!;

void main() {
  for (final theme in {'light': AppTheme.light(), 'dark': AppTheme.dark()}.entries) {
    testWidgets('a selected FilterPill reads against the tint it draws, ${theme.key}',
        (tester) async {
      late BuildContext context;
      await tester.pumpWidget(MaterialApp(
        theme: theme.value,
        home: Builder(builder: (c) {
          context = c;
          return const SizedBox.shrink();
        }),
      ));
      final brightness = Theme.of(context).brightness;
      final surface = context.cardSurface;

      for (final accent in _accents.entries) {
        // Exactly what FilterPill.build does.
        final glyph = AppTheme.semanticFor(accent.value, brightness);
        final ink = AppTheme.inkOnTintFor(accent.value, brightness);
        final painted = _over(glyph, AppTheme.alphaLight, surface);

        final ratio = _ratio(ink, painted);
        expect(ratio, greaterThanOrEqualTo(4.5),
            reason: '${accent.key}: label ${ink.toARGB32().toRadixString(16)} on '
                'the painted tint measures ${ratio.toStringAsFixed(2)}:1');
      }
    });
  }

  test('a selected SelectableChip carries white legibly', () {
    for (final accent in _accents.entries) {
      final surface = AppTheme.accentSurface(accent.value);
      final ratio = _ratio(const Color(0xFFFFFFFF), surface);
      expect(ratio, greaterThanOrEqualTo(4.5),
          reason: '${accent.key}: white on its chip fill measures '
              '${ratio.toStringAsFixed(2)}:1');
    }
  });

  test('no SelectableChip asks for an accent that has no surface', () {
    // `accentSurface` returns brandBlueSurface for anything unmapped, so a
    // coral chip would simply come out blue with nothing raised. Eight of the
    // fourteen accents are unmapped; this pins that no call site uses one.
    final unmapped = <String>{
      for (final a in _accents.entries)
        if (a.key != 'brandBlue' &&
            AppTheme.accentSurface(a.value) ==
                AppTheme.accentSurface(AppTheme.brandBlue))
          a.key,
    };

    final offenders = <String>[];
    for (final file in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      final src = file.readAsStringSync();
      for (final m in RegExp(r'SelectableChip\(').allMatches(src)) {
        final block = src.substring(
            m.start, math.min(src.length, m.start + 400));
        final accent = RegExp(r'accent:\s*AppTheme\.(\w+)').firstMatch(block);
        if (accent != null && unmapped.contains(accent.group(1))) {
          offenders.add('${file.path}: ${accent.group(1)}');
        }
      }
    }

    expect(offenders, isEmpty,
        reason: 'these would render as a blue chip: $offenders\n'
            'Add the accent to AppTheme._accentSurface, or pick a mapped one. '
            'Currently unmapped: $unmapped');
  });
}
