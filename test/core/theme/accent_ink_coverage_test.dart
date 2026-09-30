// accentInk must actually tune every accent it is handed.
//
// AppTheme.accentOnDark is `_accentOnDark[accent] ?? accent` — an unmapped
// colour comes back unchanged, and the call site cannot tell. The map covered
// six of the nine accents, so `context.accentInk(AppTheme.coral)` and
// `accentInk(AppTheme.ministryPurple)` returned the raw value: the group card's
// initials were "fixed" for two of the four group types and left alone for the
// other two, with nothing to say so.
//
// Measuring the result rather than inspecting the map, because the map being
// populated is not the point — the point is that what comes out reads against
// the tint it will be drawn on.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:notify/core/theme/app_theme.dart';
import 'package:notify/core/theme/theme_colors.dart';

/// Every design-system colour the app hands to accentInk. Adding one here
/// without a tuned pair behind it is the failure this file exists to catch.
///
/// The semantic half matters as much as the brand half: FilterPill, SwipeAction
/// and two prayer screens take a `Color accent` parameter, and their callers
/// pass AppTheme.error (8 sites) and AppTheme.mutedGrey (2) as readily as a
/// brand hue.
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

double _channel(double v) =>
    v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();

double _luminance(Color c) =>
    0.2126 * _channel(c.r) + 0.7152 * _channel(c.g) + 0.0722 * _channel(c.b);

double _ratio(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

/// [accent] at 10% over [ground] — the tint these accents are drawn on.
Color _tint(Color accent, Color ground) =>
    Color.alphaBlend(accent.withValues(alpha: 0.10), ground);

void main() {
  test('the contrast maths here is right', () {
    // Black on white is exactly 21:1, and #767676 on white is the canonical
    // 4.5:1 boundary colour. If the approximation drifts, these catch it
    // before it silently relaxes every threshold below.
    expect(_ratio(const Color(0xFF000000), const Color(0xFFFFFFFF)),
        closeTo(21.0, 0.05));
    expect(_ratio(const Color(0xFF767676), const Color(0xFFFFFFFF)),
        closeTo(4.54, 0.05));
    expect(_ratio(const Color(0xFFFFFFFF), const Color(0xFFFFFFFF)),
        closeTo(1.0, 0.01));
  });

  group('every accent is tuned, not passed through', () {
    for (final entry in _accents.entries) {
      test('${entry.key} differs from its raw value in both themes', () {
        // Dark is exempt for the four semantics whose raw value already
        // clears 4.5:1 there — warning 7.86, success 7.10, info 5.28,
        // mutedGrey 6.33. A tuned pair for those would be a colour invented
        // to satisfy a test. The contrast group below is what actually
        // guards them.
        const rawIsFineOnDark = {'warning', 'success', 'info', 'mutedGrey'};
        for (final b in Brightness.values) {
          if (b == Brightness.dark && rawIsFineOnDark.contains(entry.key)) {
            continue;
          }
          final tuned = AppTheme.semanticFor(entry.value, b);
          expect(tuned.toARGB32(), isNot(entry.value.toARGB32()),
              reason: '${entry.key} has no tuned pair for $b, so semanticFor '
                  'returned it unchanged');
        }
      });
    }
  });

  // Two tint constructions exist in the app and they are not interchangeable:
  //
  //   text  — `Container(color: AppTheme.teal.withValues(alpha: .1))` with
  //           `Text(color: context.accentInk(AppTheme.teal))`. The tint comes
  //           from the RAW accent, the ink from the tuned one. Text, so 4.5:1.
  //
  //   glyph — FilterPill, SwipeAction and the prayer tiles take one `accent`,
  //           derive `glyph = semanticFor(accent)`, and use it for BOTH the
  //           8% fill and the Icon. The tint comes from the TUNED colour, so
  //           the icon sits on a tint of itself. An icon beside its own text
  //           label is a graphical object under WCAG 1.4.11, so 3:1.
  //
  // Asserting only the first left the second unmeasured, which is how the
  // earlier numbers in this file came to describe something the app does not
  // paint.
  group('reads as a glyph on a tint of itself', () {
    const grounds = {
      Brightness.light: Color(0xFFFFFFFF),
      Brightness.dark: AppTheme.darkScaffold,
    };
    for (final entry in _accents.entries) {
      test('${entry.key} clears 3:1 as an icon on its own tint', () {
        grounds.forEach((brightness, ground) {
          final tuned = AppTheme.semanticFor(entry.value, brightness);
          // 8%, the alpha these widgets actually use.
          final fill = Color.alphaBlend(tuned.withValues(alpha: 0.08), ground);
          final ratio = _ratio(tuned, fill);
          expect(ratio, greaterThanOrEqualTo(3.0),
              reason: '${entry.key} on $brightness measures '
                  '${ratio.toStringAsFixed(2)}:1');
        });
      });
    }
  });

  group('and reads as text on a tint of the raw accent', () {
    const grounds = {
      Brightness.light: Color(0xFFFFFFFF),
      Brightness.dark: AppTheme.darkScaffold,
    };
    for (final entry in _accents.entries) {
      test('${entry.key} clears 4.5:1 as text on its own tint', () {
        grounds.forEach((brightness, ground) {
          final tuned = AppTheme.semanticFor(entry.value, brightness);
          final ratio = _ratio(tuned, _tint(entry.value, ground));
          expect(ratio, greaterThanOrEqualTo(4.5),
              reason: '${entry.key} on $brightness measures '
                  '${ratio.toStringAsFixed(2)}:1');
        });
      });
    }
  });

  // Everything above measures AppTheme.semanticFor. Nothing above goes through
  // `context.accentInk`, which is what the 98 migrated call sites actually
  // write — so the extension could stop consulting semanticFor entirely and
  // every assertion in this file would still pass. Found by mutation: replacing
  // the body of accentInk with `=> accent`, which is the exact defect this file
  // was written about, left all 712 tests green.
  //
  // These pin the delegation, in a real element tree so the brightness comes
  // from the theme the app installs rather than from a value passed in.
  group('the extension delegates', () {
    Future<BuildContext> contextFor(WidgetTester tester, ThemeData theme) async {
      late BuildContext captured;
      await tester.pumpWidget(MaterialApp(
        theme: theme,
        home: Builder(builder: (context) {
          captured = context;
          return const SizedBox.shrink();
        }),
      ));
      return captured;
    }

    for (final (label, theme) in [
      ('light', AppTheme.light()),
      ('dark', AppTheme.dark()),
    ]) {
      testWidgets('accentInk resolves every accent against the $label theme',
          (tester) async {
        final context = await contextFor(tester, theme);
        final brightness = Theme.of(context).brightness;

        for (final entry in _accents.entries) {
          expect(context.accentInk(entry.value),
              AppTheme.semanticFor(entry.value, brightness),
              reason: 'accentInk(${entry.key}) must go through semanticFor; '
                  'returning the raw accent is the bug this file is about');
        }
      });

      testWidgets('the named semantic getters resolve too, in $label',
          (tester) async {
        final context = await contextFor(tester, theme);
        final brightness = Theme.of(context).brightness;

        // Same failure mode, four more entry points: these are what the app
        // writes for error, warning, success and info text.
        expect(context.dangerText, AppTheme.semanticFor(AppTheme.error, brightness));
        expect(context.warningText, AppTheme.semanticFor(AppTheme.warning, brightness));
        expect(context.successText, AppTheme.semanticFor(AppTheme.success, brightness));
        expect(context.infoText, AppTheme.semanticFor(AppTheme.info, brightness));
      });
    }
  });
}
