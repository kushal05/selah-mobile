/// Locale-aware date and time formatting.
///
/// Replaces 17 hand-rolled helpers that each inlined an English month array:
///
/// ```dart
/// final months = ['Jan', 'Feb', ...];           // allocated on every call
/// return '${months[date.month - 1]} ${date.day}, ${date.year}';
/// ```
///
/// Twelve files carried a copy, and they disagreed: five rendered
/// "Sep 15, 2026", three "Sep 15", and one "15 Sep" — month-first and
/// day-first in the same app. None of them could ever translate, so every
/// date stayed English and US-ordered no matter the locale.
///
/// [Intl.defaultLocale] is set from the resolved app locale in main.dart's
/// MaterialApp builder, so these read the locale from the widget tree without
/// each caller having to thread a BuildContext through.
library;

import 'package:intl/intl.dart';

/// "Sep 15, 2026" in en_US, "15 Sept 2026" in en_GB, "15 sept. 2026" in fr.
String formatMediumDate(DateTime date) => DateFormat.yMMMd().format(date);

/// "Sep 15" — a date within the current year, where the year is noise.
String formatShortDate(DateTime date) => DateFormat.MMMd().format(date);

/// "Sep" — for column headers and heatmap labels.
String formatMonthAbbrev(DateTime date) => DateFormat.MMM().format(date);

/// "Sep 15, 3:06 PM" — 24-hour in locales that use it, which is most of them.
String formatDateAndTime(DateTime date) =>
    '${DateFormat.MMMd().format(date)}, ${DateFormat.jm().format(date)}';

/// "3:06 PM" in en_US, "15:06" in en_GB and most of Europe.
String formatTime(DateTime time) => DateFormat.jm().format(time);

/// "September 15, 2026" — the long form, where the abbreviation reads terse.
String formatLongDate(DateTime date) => DateFormat.yMMMMd().format(date);

/// "Monday" — the full weekday name.
String formatWeekdayLong(DateTime date) => DateFormat.EEEE().format(date);

/// "Monday, September 15" — the greeting form on the dashboards.
String formatWeekdayAndLongDate(DateTime date) =>
    DateFormat.MMMMEEEEd().format(date);
