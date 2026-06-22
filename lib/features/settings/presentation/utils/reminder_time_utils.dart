import 'package:flutter/material.dart';

/// Convert a UTC "HH:MM" string to a local [TimeOfDay]. Returns null if invalid.
TimeOfDay? reminderUtcToLocal(String? utcTime) {
  if (utcTime == null) return null;
  final parts = utcTime.split(':');
  if (parts.length != 2) return null;
  final h = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  if (h == null || m == null) return null;
  final local = DateTime.utc(2000, 1, 1, h, m).toLocal();
  return TimeOfDay(hour: local.hour, minute: local.minute);
}

/// Convert a local [TimeOfDay] to a UTC "HH:MM" string.
String reminderLocalToUtc(TimeOfDay local) {
  final now = DateTime.now();
  final utc =
      DateTime(now.year, now.month, now.day, local.hour, local.minute).toUtc();
  return '${utc.hour.toString().padLeft(2, '0')}:${utc.minute.toString().padLeft(2, '0')}';
}

/// Format a UTC "HH:MM" reminder time for display (e.g. "8:30 AM").
/// Returns "Set time" if [utcTime] is null or unparseable.
String reminderDisplayTime(String? utcTime) {
  final local = reminderUtcToLocal(utcTime);
  if (local == null) return 'Set time';
  final h = local.hourOfPeriod == 0 ? 12 : local.hourOfPeriod;
  final m = local.minute.toString().padLeft(2, '0');
  final period = local.period == DayPeriod.am ? 'AM' : 'PM';
  return '$h:$m $period';
}
