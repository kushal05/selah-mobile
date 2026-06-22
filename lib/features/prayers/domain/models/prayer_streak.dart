/// Streak stats derived from `prayer_logs` session dates. Pure value class.
class PrayerStreak {
  /// Number of consecutive days ending at "today" (or yesterday if the user
  /// hasn't logged yet today — see [currentIncludesToday]) on which the
  /// user logged at least one prayer.
  final int currentStreakDays;

  /// Whether today's date is in [activeDates]. Used to color the UI: a 7-day
  /// streak that includes today renders one way, a 7-day streak that ended
  /// yesterday renders subtly differently ("don't break it").
  final bool currentIncludesToday;

  /// All-time longest streak (consecutive days with at least one log).
  final int longestStreakDays;

  /// Total distinct days the user has ever logged a prayer.
  final int totalActiveDays;

  /// The set of YYYY-MM-DD dates with at least one prayer log within the
  /// rolling window used for the heatmap (last 12 weeks by default).
  final Set<String> activeDates;

  /// Number of days in the heatmap window.
  final int heatmapWindowDays;

  const PrayerStreak({
    required this.currentStreakDays,
    required this.currentIncludesToday,
    required this.longestStreakDays,
    required this.totalActiveDays,
    required this.activeDates,
    required this.heatmapWindowDays,
  });

  static const empty = PrayerStreak(
    currentStreakDays: 0,
    currentIncludesToday: false,
    longestStreakDays: 0,
    totalActiveDays: 0,
    activeDates: <String>{},
    heatmapWindowDays: 84,
  );
}
