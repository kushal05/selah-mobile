import 'package:drift/drift.dart';

import '../../../../core/database/sync_database.dart';
import '../../domain/models/prayer_streak.dart';

/// Computes [PrayerStreak] from the prayer_logs table.
///
/// "Active day" = any session_date with at least one non-deleted prayer log.
/// Current streak walks backward from today; if today has no log, it walks
/// backward from yesterday (so missing today doesn't break the streak until
/// tomorrow's midnight).
class PrayerStreakService {
  final SyncDatabase _db;
  PrayerStreakService(this._db);

  /// Heatmap window — 12 weeks. Anything older isn't shown but still
  /// counts toward [PrayerStreak.totalActiveDays].
  static const int heatmapWindowDays = 84;

  Future<PrayerStreak> compute({required String userId}) async {
    if (userId.isEmpty) return PrayerStreak.empty;

    final rows = await _db.customSelect(
      'SELECT DISTINCT session_date FROM prayer_logs '
      'WHERE user_id = ? AND deleted = 0 AND trashed_at IS NULL '
      'ORDER BY session_date DESC',
      variables: [Variable.withString(userId)],
      readsFrom: {_db.prayerLogs},
    ).get();

    if (rows.isEmpty) return PrayerStreak.empty;

    final allDates = rows.map((r) => r.read<String>('session_date')).toSet();

    final today = DateTime.now();
    final todayStr = _ymd(today);
    final yesterdayStr = _ymd(today.subtract(const Duration(days: 1)));

    // Walk backward from today (or yesterday if today is missing).
    var cursor = today;
    final includesToday = allDates.contains(todayStr);
    if (!includesToday) {
      // If yesterday is also missing, the current streak is 0.
      if (!allDates.contains(yesterdayStr)) {
        return _withWindow(
          PrayerStreak(
            currentStreakDays: 0,
            currentIncludesToday: false,
            longestStreakDays: _longestStreak(allDates),
            totalActiveDays: allDates.length,
            activeDates: const {},
            heatmapWindowDays: heatmapWindowDays,
          ),
          allDates,
        );
      }
      cursor = today.subtract(const Duration(days: 1));
    }

    var current = 0;
    while (allDates.contains(_ymd(cursor))) {
      current++;
      cursor = cursor.subtract(const Duration(days: 1));
    }

    return _withWindow(
      PrayerStreak(
        currentStreakDays: current,
        currentIncludesToday: includesToday,
        longestStreakDays: _longestStreak(allDates),
        totalActiveDays: allDates.length,
        activeDates: const {},
        heatmapWindowDays: heatmapWindowDays,
      ),
      allDates,
    );
  }

  /// Reduces the full date set to just the heatmap window.
  PrayerStreak _withWindow(PrayerStreak base, Set<String> allDates) {
    final now = DateTime.now();
    final windowStart = now.subtract(Duration(days: heatmapWindowDays - 1));
    final windowDates = <String>{};
    for (final d in allDates) {
      final dt = _parseYmd(d);
      if (dt == null) continue;
      if (!dt.isBefore(windowStart)) {
        windowDates.add(d);
      }
    }
    return PrayerStreak(
      currentStreakDays: base.currentStreakDays,
      currentIncludesToday: base.currentIncludesToday,
      longestStreakDays: base.longestStreakDays,
      totalActiveDays: base.totalActiveDays,
      activeDates: windowDates,
      heatmapWindowDays: heatmapWindowDays,
    );
  }

  int _longestStreak(Set<String> dates) {
    if (dates.isEmpty) return 0;
    final parsed = dates
        .map(_parseYmd)
        .whereType<DateTime>()
        .toList()
      ..sort();
    var longest = 1;
    var run = 1;
    for (var i = 1; i < parsed.length; i++) {
      final diff = parsed[i].difference(parsed[i - 1]).inDays;
      if (diff == 1) {
        run++;
        if (run > longest) longest = run;
      } else if (diff > 1) {
        run = 1;
      }
    }
    return longest;
  }

  static String _ymd(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static DateTime? _parseYmd(String s) {
    final parts = s.split('-');
    if (parts.length != 3) return null;
    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final d = int.tryParse(parts[2]);
    if (y == null || m == null || d == null) return null;
    return DateTime(y, m, d);
  }
}
