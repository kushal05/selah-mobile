import 'package:drift/drift.dart';

import '../../../../core/database/sync_database.dart';

/// Computed analytics service for prayer data.
/// All results are derived from existing tables — no new DB tables needed.
class PrayerAnalyticsService {
  final SyncDatabase _db;
  final String _userId;

  PrayerAnalyticsService(this._db, this._userId);

  /// All prayer counts in a single query using conditional aggregation.
  /// Returns total non-deleted prayers and answered count together.
  Future<({int total, int answered})> getPrayerCounts() async {
    final result = await _db.customSelect(
      'SELECT COUNT(*) as total, '
      "COALESCE(SUM(CASE WHEN status = 'answered' THEN 1 ELSE 0 END), 0) as answered "
      'FROM prayers WHERE user_id = ? AND deleted = 0',
      variables: [Variable.withString(_userId)],
    ).getSingle();
    return (
      total: result.read<int>('total'),
      answered: result.read<int>('answered'),
    );
  }

  /// Total non-deleted prayers for the user.
  Future<int> getTotalPrayers() async {
    final counts = await getPrayerCounts();
    return counts.total;
  }

  /// Count of prayers with status = 'answered'.
  Future<int> getAnsweredCount() async {
    final counts = await getPrayerCounts();
    return counts.answered;
  }

  /// Ratio of answered prayers to total (0.0–1.0). Returns 0 if no prayers.
  Future<double> getAnsweredRatio() async {
    final counts = await getPrayerCounts();
    if (counts.total == 0) return 0.0;
    return counts.answered / counts.total;
  }

  /// Heatmap: number of prayer logs per session_date for the last [days] days.
  /// Returns a map of DateTime (date only) → log count.
  Future<Map<DateTime, int>> getPrayerHeatmap({int days = 365}) async {
    final now = DateTime.now();
    final start = now.subtract(Duration(days: days));
    final startDate =
        '${start.year}-${start.month.toString().padLeft(2, '0')}-${start.day.toString().padLeft(2, '0')}';

    final rows = await _db.customSelect(
      'SELECT session_date, COUNT(*) as count FROM prayer_logs '
      'WHERE user_id = ? AND deleted = 0 AND session_date >= ? '
      'GROUP BY session_date '
      'ORDER BY session_date ASC',
      variables: [
        Variable.withString(_userId),
        Variable.withString(startDate),
      ],
    ).get();

    final map = <DateTime, int>{};
    for (final row in rows) {
      final dateStr = row.read<String>('session_date');
      final parts = dateStr.split('-');
      if (parts.length == 3) {
        final date = DateTime(
          int.parse(parts[0]),
          int.parse(parts[1]),
          int.parse(parts[2]),
        );
        map[date] = row.read<int>('count');
      }
    }
    return map;
  }

  /// Current prayer streak: consecutive days (ending today or yesterday)
  /// that have at least one prayer log.
  Future<int> getStreak() async {
    // Limit to last 366 days — a streak can't exceed that anyway
    final now = DateTime.now();
    final cutoff = now.subtract(const Duration(days: 366));
    final cutoffDate =
        '${cutoff.year}-${cutoff.month.toString().padLeft(2, '0')}-${cutoff.day.toString().padLeft(2, '0')}';

    final rows = await _db.customSelect(
      'SELECT DISTINCT session_date FROM prayer_logs '
      'WHERE user_id = ? AND deleted = 0 AND session_date >= ? '
      'ORDER BY session_date DESC',
      variables: [
        Variable.withString(_userId),
        Variable.withString(cutoffDate),
      ],
    ).get();

    if (rows.isEmpty) return 0;

    final dates = rows.map((r) {
      final parts = r.read<String>('session_date').split('-');
      return DateTime(
        int.parse(parts[0]),
        int.parse(parts[1]),
        int.parse(parts[2]),
      );
    }).toList();

    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);

    // Streak must start from today or yesterday
    final first = dates.first;
    final diff = todayDate.difference(first).inDays;
    if (diff > 1) return 0;

    int streak = 1;
    for (int i = 1; i < dates.length; i++) {
      final gap = dates[i - 1].difference(dates[i]).inDays;
      if (gap == 1) {
        streak++;
      } else {
        break;
      }
    }
    return streak;
  }

  /// Prayers with the most log entries (top N by frequency).
  Future<List<({String prayerId, String title, int logCount})>>
      getFrequentlyPrayed({int limit = 10}) async {
    final rows = await _db.customSelect(
      'SELECT p.id, p.title, COUNT(l.id) as log_count '
      'FROM prayers p '
      'INNER JOIN prayer_logs l ON l.prayer_id = p.id AND l.deleted = 0 '
      'WHERE p.user_id = ? AND p.deleted = 0 '
      'GROUP BY p.id '
      'ORDER BY log_count DESC '
      'LIMIT ?',
      variables: [
        Variable.withString(_userId),
        Variable.withInt(limit),
      ],
    ).get();

    return rows.map((row) {
      return (
        prayerId: row.read<String>('id'),
        title: row.read<String>('title'),
        logCount: row.read<int>('log_count'),
      );
    }).toList();
  }
}
