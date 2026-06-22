// ── Habit category string constants (must match Go backend and FCM worker) ──────
const habitCategoryBibleReading = 'habit_bible_reading';
const habitCategoryMeditation = 'habit_meditation';

/// Domain model for a single notification preference.
class NotificationPreference {
  final String category;
  final bool enabled;
  final String? reminderTime; // "HH:MM" UTC, only for habit categories

  const NotificationPreference({
    required this.category,
    required this.enabled,
    this.reminderTime,
  });

  factory NotificationPreference.fromJson(Map<String, dynamic> json) {
    return NotificationPreference(
      category: json['category'] as String,
      enabled: json['enabled'] as bool? ?? true,
      reminderTime: json['reminderTime'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'category': category,
        'enabled': enabled,
        if (reminderTime != null) 'reminderTime': reminderTime,
      };

  NotificationPreference copyWith({
    bool? enabled,
    String? reminderTime,
    bool clearReminderTime = false,
  }) {
    return NotificationPreference(
      category: category,
      enabled: enabled ?? this.enabled,
      reminderTime:
          clearReminderTime ? null : (reminderTime ?? this.reminderTime),
    );
  }
}
