import '../domain/enums/prayer_enums.dart';
import '../../core/sync/models/prayer_model.dart';
import '../../core/sync/repositories/prayer_repository.dart';
import 'notification_service.dart';

/// Service for scheduling prayer reminders based on prayer frequency
class PrayerReminderService {
  final NotificationService _notificationService;
  final PrayerRepository _prayerRepo;
  final String _userId;

  static const int _defaultHour = 8;
  static const int _defaultMinute = 0;

  PrayerReminderService({
    required NotificationService notificationService,
    required PrayerRepository prayerRepo,
    required String userId,
  })  : _notificationService = notificationService,
        _prayerRepo = prayerRepo,
        _userId = userId;

  /// Generate a stable notification ID from a prayer ID string
  int _notificationId(String prayerId) {
    return prayerId.hashCode & 0x7FFFFFFF;
  }

  /// Schedule a reminder for a prayer based on its frequency
  Future<void> schedulePrayerReminder(PrayerModel prayer) async {
    await schedulePrayerReminderAt(prayer);
  }

  /// Schedule a reminder for a prayer based on its frequency.
  /// If [preferredTime] is provided, that time is used instead of defaults.
  Future<void> schedulePrayerReminderAt(
    PrayerModel prayer, {
    DateTime? preferredTime,
  }) async {
    if (!prayer.isActive) return;

    final id = _notificationId(prayer.id);
    final title = 'Prayer Reminder';
    final body = prayer.title;
    final hour = preferredTime?.hour ?? _defaultHour;
    final minute = preferredTime?.minute ?? _defaultMinute;

    // Cancel any existing reminder first
    await _notificationService.cancelNotification(id);

    switch (prayer.frequency) {
      case PrayerFrequency.daily:
        await _notificationService.scheduleDaily(
          id: id,
          title: title,
          body: body,
          hour: hour,
          minute: minute,
        );
      case PrayerFrequency.weekdays:
        // Schedule Mon-Fri (weekday 1-5)
        for (var day = 1; day <= 5; day++) {
          await _notificationService.scheduleWeekly(
            id: id + day,
            title: title,
            body: body,
            weekday: day,
            hour: hour,
            minute: minute,
          );
        }
      case PrayerFrequency.weekly:
        // Schedule every Sunday (weekday 7)
        await _notificationService.scheduleWeekly(
          id: id,
          title: title,
          body: body,
          weekday: DateTime.sunday,
          hour: hour,
          minute: minute,
        );
      case PrayerFrequency.monthly:
        await _notificationService.scheduleMonthly(
          id: id,
          title: title,
          body: body,
          hour: hour,
          minute: minute,
        );
      case PrayerFrequency.asNeeded:
        // No automatic reminder for as-needed prayers
        break;
    }
  }

  /// Cancel reminder for a prayer
  Future<void> cancelPrayerReminder(String prayerId) async {
    final id = _notificationId(prayerId);
    await _notificationService.cancelNotification(id);
    // Also cancel weekday sub-IDs (used for weekdays frequency)
    for (var day = 1; day <= 5; day++) {
      await _notificationService.cancelNotification(id + day);
    }
  }

  /// Reschedule all active prayer reminders
  /// Call on app start to ensure reminders are current
  Future<void> rescheduleAll() async {
    await _notificationService.cancelAll();
    final prayers = await _prayerRepo.getActivePrayers(_userId);
    for (final prayer in prayers) {
      await schedulePrayerReminder(prayer);
    }
  }
}
