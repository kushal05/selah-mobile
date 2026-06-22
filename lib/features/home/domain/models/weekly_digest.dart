/// Aggregated activity over the user's last [days] days. Pure value class —
/// the math lives in `WeeklyDigestService.compute()` and the rendering lives
/// in `WeeklyDigestScreen`.
class WeeklyDigest {
  final DateTime windowStart;
  final DateTime windowEnd;
  final int days;

  /// Number of distinct prayer-log entries in the window.
  final int prayersLogged;

  /// Distinct days within the window on which at least one prayer was logged.
  final int prayerDaysActive;

  /// Prayers whose `answeredAt` falls inside the window.
  final int prayersAnswered;

  /// Notes whose `createdAt` falls inside the window.
  final int notesCreated;

  /// Notes whose `updatedAt` falls inside the window (and were not created
  /// in the same window — counted as separate edits).
  final int notesEdited;

  /// Distinct Bible chapters opened in the window (book + chapter pair).
  final int chaptersOpened;

  /// Distinct people referenced in any prayer-person link created in window.
  final int peopleMentioned;

  /// Top three book/chapter strings opened most often.
  final List<String> topChapters;

  /// Top three prayer titles logged most often.
  final List<String> topPrayerTitles;

  const WeeklyDigest({
    required this.windowStart,
    required this.windowEnd,
    required this.days,
    required this.prayersLogged,
    required this.prayerDaysActive,
    required this.prayersAnswered,
    required this.notesCreated,
    required this.notesEdited,
    required this.chaptersOpened,
    required this.peopleMentioned,
    required this.topChapters,
    required this.topPrayerTitles,
  });

  bool get isEmpty =>
      prayersLogged == 0 &&
      prayersAnswered == 0 &&
      notesCreated == 0 &&
      notesEdited == 0 &&
      chaptersOpened == 0 &&
      peopleMentioned == 0;
}
