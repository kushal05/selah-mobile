import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;

/// Service for managing local notifications
class NotificationService {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  /// Initialize the notification plugin with platform-specific settings
  Future<void> initialize() async {
    if (_initialized) return;

    tz_data.initializeTimeZones();

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _plugin.initialize(settings);
    await _createAndroidChannels();
    _initialized = true;
  }

  /// Pre-create all Android notification channels so FCM can use them
  /// immediately — even before the first local notification is shown.
  Future<void> _createAndroidChannels() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return;

    const channels = [
      AndroidNotificationChannel(
        'notify_reminders',
        'Reminders',
        description: 'Daily habit and prayer reminders',
        importance: Importance.high,
      ),
      AndroidNotificationChannel(
        'notify_social',
        'Social',
        description: 'Friend requests, group invites, and more',
        importance: Importance.defaultImportance,
      ),
      AndroidNotificationChannel(
        'notify_general',
        'General',
        description: 'General notifications',
        importance: Importance.defaultImportance,
      ),
      AndroidNotificationChannel(
        'notify_prayer_reminders',
        'Prayer Reminders',
        description: 'Reminders for your prayer times',
        importance: Importance.high,
      ),
    ];

    for (final channel in channels) {
      await android.createNotificationChannel(channel);
    }
  }

  /// Request notification permissions (primarily for iOS/Android 13+)
  Future<bool> requestPermission() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      final granted = await android.requestNotificationsPermission();
      return granted ?? false;
    }
    return true;
  }

  /// Show an immediate notification
  Future<void> showNotification({
    required int id,
    required String title,
    required String body,
  }) async {
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'notify_general',
        'General',
        channelDescription: 'General notifications',
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
      ),
      iOS: DarwinNotificationDetails(),
    );
    await _plugin.show(id, title, body, details);
  }

  /// Schedule a daily notification at a specific time
  Future<void> scheduleDaily({
    required int id,
    required String title,
    required String body,
    required int hour,
    required int minute,
  }) async {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );
    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }

    await _plugin.zonedSchedule(
      id,
      title,
      body,
      scheduled,
      _prayerNotificationDetails,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  /// Schedule a weekly notification on a specific day and time
  Future<void> scheduleWeekly({
    required int id,
    required String title,
    required String body,
    required int weekday,
    required int hour,
    required int minute,
  }) async {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );
    // Advance to the target weekday
    while (scheduled.weekday != weekday) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 7));
    }

    await _plugin.zonedSchedule(
      id,
      title,
      body,
      scheduled,
      _prayerNotificationDetails,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
    );
  }

  /// Schedule a monthly notification on the 1st of each month at a specific time
  Future<void> scheduleMonthly({
    required int id,
    required String title,
    required String body,
    required int hour,
    required int minute,
  }) async {
    final now = tz.TZDateTime.now(tz.local);
    // Schedule for the 1st of the current or next month
    var scheduled = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      1,
      hour,
      minute,
    );
    if (scheduled.isBefore(now)) {
      // Move to 1st of next month
      final nextMonth = now.month == 12 ? 1 : now.month + 1;
      final nextYear = now.month == 12 ? now.year + 1 : now.year;
      scheduled = tz.TZDateTime(tz.local, nextYear, nextMonth, 1, hour, minute);
    }

    await _plugin.zonedSchedule(
      id,
      title,
      body,
      scheduled,
      _prayerNotificationDetails,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.dayOfMonthAndTime,
    );
  }

  /// Cancel a specific notification
  Future<void> cancelNotification(int id) async {
    await _plugin.cancel(id);
  }

  /// Cancel all notifications
  Future<void> cancelAll() async {
    await _plugin.cancelAll();
  }

  /// Display a foreground notification for an incoming FCM [RemoteMessage].
  ///
  /// Uses the `notify_social` channel for social/collaboration messages and
  /// `notify_reminders` for habit/prayer reminders; falls back to
  /// `notify_general` for unknown types.
  Future<void> showFcmNotification(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;

    final title = notification.title ?? '';
    final body = notification.body ?? '';
    final type = message.data['type'] as String? ?? '';

    final details = _detailsForType(type);
    await _plugin.show(
      message.hashCode,
      title,
      body,
      details,
      payload: type,
    );
  }

  NotificationDetails _detailsForType(String type) {
    if (type.startsWith('social_') || type == 'prayer_collaborator') {
      return const NotificationDetails(
        android: AndroidNotificationDetails(
          'notify_social',
          'Social',
          channelDescription: 'Friend requests, group invites, and more',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
        iOS: DarwinNotificationDetails(),
      );
    }
    if (type.startsWith('habit_')) {
      return const NotificationDetails(
        android: AndroidNotificationDetails(
          'notify_reminders',
          'Reminders',
          channelDescription: 'Daily habit and prayer reminders',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      );
    }
    return const NotificationDetails(
      android: AndroidNotificationDetails(
        'notify_general',
        'General',
        channelDescription: 'General notifications',
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
      ),
      iOS: DarwinNotificationDetails(),
    );
  }

  NotificationDetails get _prayerNotificationDetails {
    return const NotificationDetails(
      android: AndroidNotificationDetails(
        'notify_prayer_reminders',
        'Prayer Reminders',
        channelDescription: 'Reminders for your prayer times',
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(),
    );
  }
}
