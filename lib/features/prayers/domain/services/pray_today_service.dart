import '../../../../core/domain/enums/prayer_enums.dart';
import '../../../../core/sync/models/prayer_model.dart';
import '../../../../core/sync/repositories/prayer_repository.dart';

/// Single source of truth for "which prayers are due today".
///
/// The qualification rules used to live inlined in `PrayTodayScreen`. They are
/// extracted here so the in-app "Pray Today" screen and the home-screen
/// "Today's Prayers" widget compute the exact same set — they can never drift.
class PrayTodayService {
  PrayTodayService(this._prayerRepo);

  final PrayerRepository _prayerRepo;

  /// Whether [prayer] should appear in today's list given the [now] reference.
  ///
  /// Pure function (no I/O) so it is trivially unit-testable across every
  /// [PrayerFrequency].
  bool qualifiesForToday(PrayerModel prayer, DateTime now) {
    switch (prayer.frequency) {
      case PrayerFrequency.daily:
        return true;
      case PrayerFrequency.weekdays:
        return now.weekday >= DateTime.monday && now.weekday <= DateTime.friday;
      case PrayerFrequency.weekly:
        // Qualify on the same weekday as creation.
        final created = DateTime.fromMillisecondsSinceEpoch(prayer.createdAt);
        return now.weekday == created.weekday;
      case PrayerFrequency.monthly:
        // Qualify on the same day-of-month as creation.
        final created = DateTime.fromMillisecondsSinceEpoch(prayer.createdAt);
        return now.day == created.day;
      case PrayerFrequency.asNeeded:
        // Only qualify on the day it was created.
        final created = DateTime.fromMillisecondsSinceEpoch(prayer.createdAt);
        return created.year == now.year &&
            created.month == now.month &&
            created.day == now.day;
    }
  }

  /// The active prayers that qualify for today, ordered as the repository
  /// returns them (most-recently-updated first).
  Future<List<PrayerModel>> todaysPrayers(
    String userId, {
    DateTime? now,
  }) async {
    if (userId.isEmpty) return const [];
    final reference = now ?? DateTime.now();
    final active = await _prayerRepo.getActivePrayers(userId);
    return active.where((p) => qualifiesForToday(p, reference)).toList();
  }
}
