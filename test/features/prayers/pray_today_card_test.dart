// A Pray Today card: its controls line up, and a long prayer can be read in place.
//
// Three things were wrong with the card. The heart badge, the log button and
// the overflow did not share a centre line: the trailing row took its height
// from the overflow's 48pt default and centred the 40pt log button in that,
// while the 44pt badge sat at the top. A long description could only be read
// by leaving the session for the prayer's detail page. And in dark mode the
// overflow's ⋮ was near-black on a dark card. These measure each.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsNode;
import 'package:flutter_test/flutter_test.dart';

import 'package:notify/core/domain/enums/prayer_enums.dart';
import 'package:notify/core/sync/models/prayer_model.dart';
import 'package:notify/core/theme/app_theme.dart';
import 'package:notify/features/prayers/domain/models/prayer_metadata_codec.dart';
import 'package:notify/features/prayers/presentation/widgets/pray_today_card.dart';
import 'package:notify/l10n/l10n.dart';

const _long = 'Pray for her recovery after the surgery next week, for the '
    'doctors guiding her treatment, and for peace for the whole family.';

PrayerModel _prayer(String content, {List<String> tags = const []}) =>
    PrayerModel(
      id: 'p1',
      userId: 'u1',
      title: 'Healing for Mom',
      content: content,
      category: tags.isEmpty
          ? null
          : encodePrayerMetadata(PrayerMetadata(tags: tags)),
      frequency: PrayerFrequency.daily,
      status: PrayerStatus.active,
      updatedAt: 0,
      version: 1,
      deleted: 0,
      createdAt: 0,
    );

/// Pumps one card, recording taps on it and on its expand control.
Future<({List<String> taps})> _pump(
  WidgetTester tester, {
  String content = _long,
  List<String> tags = const [],
  bool expanded = false,
  ThemeData? theme,
  double textScale = 1.0,
  double width = 390,
}) async {
  tester.view.physicalSize = Size(width * 3, 900 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final taps = <String>[];
  await tester.pumpWidget(MaterialApp(
    theme: theme ?? AppTheme.light(),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    builder: (c, child) => MediaQuery(
      data: MediaQuery.of(c)
          .copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: Scaffold(
      body: ListView(children: [
        PrayTodayCard(
          prayer: _prayer(content, tags: tags),
          isLogged: false,
          onLogPress: () => taps.add('log'),
          onTap: () => taps.add('open detail'),
          onMarkAnswered: () {},
          onArchive: () {},
          isExpanded: expanded,
          onToggleExpanded: () => taps.add('toggle'),
        ),
      ]),
    ),
  ));
  await tester.pumpAndSettle();
  return (taps: taps);
}

final _badge = find.byIcon(Icons.favorite_outline_rounded);
final _logButton = find.byIcon(Icons.check_rounded);
final _overflow = find.byIcon(Icons.more_vert_rounded);
final _arrowDown = find.byIcon(Icons.expand_more_rounded);
final _arrowUp = find.byIcon(Icons.expand_less_rounded);

/// The card's own surface: the InkWell that opens the prayer.
Rect _card(WidgetTester tester, Finder inside) => tester.getRect(
    find.ancestor(of: inside, matching: find.byType(InkWell)).last);

/// The description's tap area.
Rect _toggleArea(WidgetTester tester) => tester.getRect(find
    .ancestor(of: find.text(_long), matching: find.byType(GestureDetector))
    .first);

/// The description's Text, found by its content.
Text _descriptionText(WidgetTester tester) =>
    tester.widget<Text>(find.text(_long));

void main() {
  group('the controls', () {
    testWidgets('share one centre line', (tester) async {
      await _pump(tester);
      double cy(Finder f) => tester.getCenter(f).dy;

      expect(cy(_logButton), closeTo(cy(_badge), 0.5),
          reason: 'the log button sat lower than the badge');
      expect(cy(_overflow), closeTo(cy(_badge), 0.5),
          reason: 'so did the overflow');
    });

    testWidgets('and the arrow sits in the column under the ⋮',
        (tester) async {
      await _pump(tester);
      expect(tester.getCenter(_arrowDown).dx,
          closeTo(tester.getCenter(_overflow).dx, 0.5));
    });

    testWidgets('and the log button is a full 44pt target round a 40pt circle',
        (tester) async {
      final r = await _pump(tester);
      final target = find.ancestor(of: _logButton, matching: find.byType(InkWell));
      expect(tester.getSize(target.first),
          const Size.square(AppTheme.minTapTarget));
      expect(
          tester.getSize(
              find.ancestor(of: _logButton, matching: find.byType(Ink)).first),
          const Size.square(40),
          reason: 'the circle drawn stays the size it was');

      // Outside the drawn circle, inside the target.
      await tester.tapAt(tester.getCenter(_logButton) + const Offset(21, 0));
      expect(r.taps, ['log']);
    });

    testWidgets('and the ⋮ can be seen in dark mode', (tester) async {
      // It took Material's default black: the dark theme sets icon colours only
      // inside its app bar. A glyph needs 3:1 against what it sits on.
      await _pump(tester, theme: AppTheme.dark());
      final ctx = tester.element(_overflow);
      final color = IconTheme.of(ctx).color!;
      final card = AppTheme.dark().cardTheme.color ??
          AppTheme.dark().colorScheme.surface;

      double lum(Color c) {
        double l(double v) => v <= 0.03928
            ? v / 12.92
            : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
        final a = c.a;
        // Composite over the card: the icon colour can carry alpha.
        double ch(double fg, double bg) => fg * a + bg * (1 - a);
        return 0.2126 * l(ch(c.r, card.r)) +
            0.7152 * l(ch(c.g, card.g)) +
            0.0722 * l(ch(c.b, card.b));
      }

      final lc = lum(color), lb = lum(card);
      final ratio = (math.max(lc, lb) + 0.05) / (math.min(lc, lb) + 0.05);
      expect(ratio, greaterThanOrEqualTo(3.0),
          reason: 'the ⋮ measured ${ratio.toStringAsFixed(2)}:1 on the card');
    });
  });

  group('a long description', () {
    testWidgets('shows one line, ending in "…", with an arrow', (tester) async {
      await _pump(tester);
      final t = _descriptionText(tester);
      expect(t.maxLines, 1);
      expect(t.overflow, TextOverflow.ellipsis);
      expect(_arrowDown, findsOneWidget);
    });

    testWidgets('runs the full width of the card, not between the controls',
        (tester) async {
      // Squeezed between the badge and the log button it showed three words.
      await _pump(tester);
      final text = tester.getRect(find.text(_long));
      final log = tester.getRect(_logButton);
      expect(text.right, greaterThan(log.left),
          reason: 'the line should run on under the controls');
    });

    testWidgets('opens in place — tapping it does not leave for the detail page',
        (tester) async {
      final r = await _pump(tester);
      await tester.tap(find.text(_long));
      await tester.pump();
      expect(r.taps, ['toggle'], reason: 'toggle, and nothing else');
    });

    testWidgets('and the arrow alone toggles too', (tester) async {
      final r = await _pump(tester);
      await tester.tap(_arrowDown);
      await tester.pump();
      expect(r.taps, ['toggle']);
    });

    testWidgets('its tap area is at least 44pt tall', (tester) async {
      await _pump(tester);
      final area = find.ancestor(
        of: find.text(_long),
        matching: find.byType(GestureDetector),
      ).first;
      expect(tester.getSize(area).height,
          greaterThanOrEqualTo(AppTheme.minTapTarget));
    });

    testWidgets('opened, shows all of it and an arrow to close it',
        (tester) async {
      await _pump(tester, expanded: true);
      expect(_descriptionText(tester).maxLines, isNull);
      expect(_arrowUp, findsOneWidget);
      expect(_arrowDown, findsNothing);
    });

    testWidgets('and its arrow does not move between the two states',
        (tester) async {
      // Beside the first line either way, so it stays under the finger.
      await _pump(tester);
      final closed = tester.getCenter(_arrowDown);
      await _pump(tester, expanded: true);
      final open = tester.getCenter(_arrowUp);
      expect(open, offsetMoreOrLessEquals(closed, epsilon: 0.5));
    });

    testWidgets('is announced as expandable', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester);
      SemanticsNode node() => tester.getSemantics(find.ancestor(
            of: find.text(_long),
            matching: find.byType(Semantics),
          ).first);
      expect(node(), isSemantics(
          isButton: true, hasExpandedState: true, isExpanded: false));

      await _pump(tester, expanded: true);
      expect(node(), isSemantics(
          isButton: true, hasExpandedState: true, isExpanded: true));
      handle.dispose();
    });
  });

  group('a long description, closed, with no tags', () {
    testWidgets("its tap area runs down to the card's edge", (tester) async {
      await _pump(tester);
      expect(_toggleArea(tester).bottom,
          closeTo(_card(tester, find.text(_long)).bottom, 0.5));
    });

    testWidgets('leaves no more room below it than the 44pt floor needs',
        (tester) async {
      // Held to 44pt on its own, the line left a 20pt band of nothing above
      // the card's own bottom padding.
      await _pump(tester);
      final text = tester.getRect(find.text(_long));
      final gap = _card(tester, find.text(_long)).bottom - text.bottom;
      final floor = AppTheme.minTapTarget - AppTheme.spacing7 - text.height;
      expect(gap,
          closeTo(math.max(AppTheme.cardPadding.bottom, floor), 0.5));
    });

    testWidgets("a tap in the card's bottom padding opens it", (tester) async {
      final r = await _pump(tester);
      final card = _card(tester, find.text(_long));
      await tester.tapAt(Offset(tester.getCenter(find.text(_long)).dx,
          card.bottom - 3));
      await tester.pump();
      expect(r.taps, ['toggle']);
    });
  });

  group('a long description with tags', () {
    const tags = ['Family', 'Health'];

    testWidgets('keeps the tags as close below it as a short one does',
        (tester) async {
      await _pump(tester, tags: tags);
      final gap = tester.getTopLeft(find.text('Family')).dy -
          tester.getRect(find.text(_long)).bottom;
      await _pump(tester, content: 'Wisdom at work.', tags: tags);
      final short = tester.getTopLeft(find.text('Family')).dy -
          tester.getRect(find.text('Wisdom at work.')).bottom;
      expect(gap, closeTo(short, 0.5));
    });

    testWidgets("keeps the card's bottom padding below the tags",
        (tester) async {
      final r = await _pump(tester, tags: tags);
      final card = _card(tester, find.text(_long));
      expect(card.bottom - tester.getRect(find.text('Family')).bottom,
          greaterThanOrEqualTo(AppTheme.cardPadding.bottom));
      // And that padding is part of the tap area too.
      await tester.tapAt(Offset(
          tester.getCenter(find.text('Family')).dx, card.bottom - 3));
      await tester.pump();
      expect(r.taps, ['toggle']);
    });

    testWidgets('takes the tags into its tap area', (tester) async {
      final r = await _pump(tester, tags: tags);
      await tester.tap(find.text('Family'));
      await tester.pump();
      expect(r.taps, ['toggle']);
    });

    testWidgets('but does not read them out as part of its button',
        (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, tags: tags);
      final node = tester.getSemantics(find.text(_long));
      expect(node.label, isNot(contains('Family')));
      expect(node.flagsCollection.isButton, isTrue);
      handle.dispose();
    });
  });

  group('a short description', () {
    testWidgets("keeps the card's bottom padding below it", (tester) async {
      await _pump(tester, content: 'Wisdom at work.');
      expect(
          _card(tester, find.text('Wisdom at work.')).bottom -
              tester.getRect(find.text('Wisdom at work.')).bottom,
          closeTo(AppTheme.cardPadding.bottom, 0.5));
    });

    testWidgets('with tags, a tap on them still opens the prayer',
        (tester) async {
      final r = await _pump(tester, content: 'Wisdom at work.', tags: ['Work']);
      await tester.tap(find.text('Work'));
      await tester.pump();
      expect(r.taps, ['open detail']);
      expect(
          _card(tester, find.text('Work')).bottom -
              tester.getRect(find.text('Work')).bottom,
          greaterThanOrEqualTo(AppTheme.cardPadding.bottom),
          reason: 'the bottom padding is still there below the tags');
    });

    testWidgets('that fits on one line has no arrow and nothing to tap',
        (tester) async {
      final r = await _pump(tester, content: 'Wisdom at work.');
      expect(_arrowDown, findsNothing);
      await tester.tap(find.text('Wisdom at work.'));
      await tester.pump();
      expect(r.taps, ['open detail'],
          reason: 'with nothing to open, a tap opens the prayer as before');
    });

    testWidgets('but gets one when larger text no longer fits it',
        (tester) async {
      // Measured at the reader's text size: a description that fits at 100%
      // has to offer the arrow once it is cut off at 160%.
      // Short by the app's standard, because tests render in Ahem — every
      // glyph a full square — so text runs far wider than on a device.
      const borderline = 'Pray for peace';
      await _pump(tester, content: borderline);
      expect(_arrowDown, findsNothing,
          reason: 'precondition: fits on one line at normal size');

      await _pump(tester, content: borderline, textScale: 1.6);
      expect(_arrowDown, findsOneWidget);
    });
  });
}
