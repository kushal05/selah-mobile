// Colours that were hard-coded and unreadable in one theme must stay out.
//
// Each pattern below was found, in an audit of the app, painting text, icons or
// fills that do not follow the theme: a fixed grey on a dialog that is dark in
// the dark theme (3.3:1), a near-black on a dialog that is dark (1.05:1), pale
// "white" cards under light text. Every one has a theme token that is tuned for
// both themes (context.mutedText, primaryText, cardSurface, subtleFill, the
// semantic getters, accentInk, AppTheme.onAccent), so a literal in its place is
// a regression rather than a choice.
//
// This is a tripwire, not a lint rule: a deliberately fixed colour (white on an
// accent fill, the auth screens' navy backdrop, the highlight palette, PDF paper)
// is fine and is not matched here.

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:notify/core/theme/app_theme.dart';

/// Patterns that must not appear in lib/ outside the theme itself.
final _forbidden = <String, RegExp>{
  'the grey #6B7280 used as text on dialogs': RegExp(r'Color\(0xFF6B7280\)'),
  'the near-black #111827 used as text': RegExp(r'Color\(0xFF111827\)'),
  'Colors.black87 as a colour': RegExp(r'Colors\.black87'),
  'a hard-coded near-white card under theme text':
      RegExp(r'Colors\.grey\.shade50'),
  'a grey tab label that ignores the theme':
      RegExp(r'unselectedLabelColor:\s*Colors\.grey'),
  'raw Material orange/deepOrange banners':
      RegExp(r'Colors\.(orange|deepOrange)\.shade(50|200)'),
  // White on brandPurple is 4.2:1, short of the 4.5:1 text needs. A button,
  // badge or FAB that carries text fills with AppTheme.accentSurface instead.
  'a raw brandPurple fill under text':
      RegExp(r'backgroundColor:\s*AppTheme\.brandPurple\s*,'),
};

Iterable<File> _libFiles() => Directory('lib')
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) =>
        f.path.endsWith('.dart') &&
        !f.path.endsWith('.g.dart') &&
        !f.path.replaceAll('\\', '/').contains('lib/core/theme/'));

void main() {
  for (final entry in _forbidden.entries) {
    test('no ${entry.key}', () {
      final hits = <String>[];
      for (final f in _libFiles()) {
        final lines = f.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          if (line.trimLeft().startsWith('//')) continue;
          if (entry.value.hasMatch(line)) {
            hits.add('${f.path}:${i + 1}: ${line.trim()}');
          }
        }
      }
      expect(hits, isEmpty,
          reason: 'use a theme token instead:\n${hits.join('\n')}');
    });
  }

  group('white-on-fill contrast, measured', () {
    double channel(double v) => v <= 0.03928
        ? v / 12.92
        : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
    double lum(Color c) =>
        0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
    double ratio(Color a, Color b) {
      final la = lum(a), lb = lum(b);
      return ((la > lb ? la : lb) + 0.05) / ((la > lb ? lb : la) + 0.05);
    }

    test('the raw brand purple is short of 4.5:1 under white (why it is not used)',
        () {
      expect(ratio(Colors.white, AppTheme.brandPurple), lessThan(4.5));
    });

    test('the purple fill used under text clears 4.5:1 with its own ink', () {
      final fill = AppTheme.accentSurface(AppTheme.brandPurple);
      final ink = AppTheme.onAccent(fill);
      expect(ink, Colors.white);
      expect(ratio(ink, fill), greaterThanOrEqualTo(4.5));
    });

    test('the dark theme primary carries its own onPrimary, not white', () {
      final scheme = AppTheme.dark().colorScheme;
      expect(ratio(scheme.onPrimary, scheme.primary), greaterThanOrEqualTo(4.5));
      expect(ratio(Colors.white, scheme.primary), lessThan(4.5),
          reason: 'hard-coded white on the dark primary is what failed');
    });
  });
}
