// Pins the output of the shared date helpers against what the 17 hand-rolled
// versions produced, so the consolidation is provably behaviour-preserving in
// English rather than merely compiling.

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:notify/shared/utils/date_format.dart';

void main() {
  // Mirrors main(): DateFormat throws for any locale whose data is not loaded.
  setUpAll(() async => initializeDateFormatting());
  setUp(() => Intl.defaultLocale = 'en_US');

  final d = DateTime(2026, 9, 15, 15, 6);

  test('medium date matches the old "MMM d, yyyy"', () {
    expect(formatMediumDate(d), 'Sep 15, 2026');
  });

  test('short date matches the old "MMM d"', () {
    expect(formatShortDate(d), 'Sep 15');
  });

  test('month abbreviation matches the old months[i]', () {
    expect(formatMonthAbbrev(d), 'Sep');
  });

  test('long date matches the old full-month form', () {
    expect(formatLongDate(d), 'September 15, 2026');
  });

  test('weekday matches the old weekdays[i]', () {
    expect(formatWeekdayLong(DateTime(2026, 9, 14)), 'Monday');
  });

  test('weekday + long date matches the old dashboard greeting', () {
    expect(formatWeekdayAndLongDate(DateTime(2026, 9, 14)),
        'Monday, September 14');
  });

  test('date and time replaces the hand-rolled 12-hour clock', () {
    expect(formatDateAndTime(d), matches(r'^Sep 15, 3:06\sPM$'),
        reason: 'jm() separates the meridiem with U+202F, not a plain space');
  });

  // The point of the change: these follow the locale instead of being frozen
  // in US English. A different locale must produce a different string.
  test('formatting follows the locale', () {
    Intl.defaultLocale = 'en_GB';
    expect(formatMediumDate(d), isNot('Sep 15, 2026'));
    expect(formatTime(d), '15:06', reason: 'en_GB uses a 24-hour clock');
    Intl.defaultLocale = 'fr';
    expect(formatMonthAbbrev(d), isNot('Sep'),
        reason: 'month names must translate, which a months[] array never did');
  });
}
