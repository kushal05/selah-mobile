import 'dart:async';

import 'package:drift/drift.dart';

import '../../../../core/database/sync_database.dart';
import '../../../../core/sync/utils/sync_logger.dart';
import '../../../prayers/data/services/prayer_streak_service.dart';

/// Lightweight snapshot of what a paired watch needs to render its three
/// faces: today's verse line, the pray-today checklist, and the streak.
/// Stays intentionally small (≤2KB serialized) — watches sample data over
/// constrained transports and oversized messages get dropped.
class WatchPayload {
  final int streakDays;
  final bool streakIncludesToday;
  final List<WatchPrayerItem> prayerChecklist;
  final String? versePreview;
  final int updatedAt;

  const WatchPayload({
    required this.streakDays,
    required this.streakIncludesToday,
    required this.prayerChecklist,
    required this.versePreview,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() => {
        'streakDays': streakDays,
        'streakIncludesToday': streakIncludesToday,
        'prayerChecklist': prayerChecklist
            .map((p) => {'id': p.id, 'title': p.title, 'loggedToday': p.loggedToday})
            .toList(),
        'versePreview': versePreview,
        'updatedAt': updatedAt,
      };
}

class WatchPrayerItem {
  final String id;
  final String title;
  final bool loggedToday;
  const WatchPrayerItem({
    required this.id,
    required this.title,
    required this.loggedToday,
  });
}

/// Computes a [WatchPayload] from local data and (eventually) ships it to a
/// paired watch over WatchConnectivity / Wear OS DataApi.
///
/// **Wiring (not done in this commit — requires native platform):**
///   1. Add the `watch_connectivity` package to `pubspec.yaml`.
///   2. Call [refresh] on auth changes, prayer-log writes, and from
///      `SyncService.onAppPaused()` so the watch receives the latest state
///      whenever the phone backgrounds.
///   3. Replace [_send] with the WatchConnectivity write — JSON payload via
///      `updateApplicationContext()` for slow-changing data or `sendMessage()`
///      for "give me an update now" pulls initiated by the watch.
///   4. On the watch side, decode the JSON and render three faces.
///
/// Until step 3 is shipped, [_send] is a no-op log so the rest of the app
/// can wire calls in without crashing.
class WatchBridgeService {
  /// Hard cap on items shipped to the watch. Three checklist rows fit
  /// comfortably on a 40mm face; more is unreadable.
  static const int _maxChecklistItems = 5;

  final SyncDatabase _db;
  final PrayerStreakService _streakService;

  WatchBridgeService({
    required SyncDatabase db,
    required PrayerStreakService streakService,
  })  : _db = db,
        _streakService = streakService;

  Future<void> refresh({required String userId}) async {
    if (userId.isEmpty) return;
    try {
      final payload = await _buildPayload(userId);
      await _send(payload);
    } catch (e, st) {
      SyncLogger.warning('Watch bridge refresh failed: $e\n$st');
    }
  }

  Future<WatchPayload> _buildPayload(String userId) async {
    final streak = await _streakService.compute(userId: userId);
    final today = _ymd(DateTime.now());

    // Active prayers, with a flag indicating whether they were already
    // logged today (so the watch can render a check vs an empty bubble).
    final rows = await _db.customSelect(
      'SELECT p.id, p.title, '
      '  EXISTS(SELECT 1 FROM prayer_logs l '
      '         WHERE l.prayer_id = p.id AND l.user_id = p.user_id '
      '         AND l.deleted = 0 AND l.session_date = ?) AS logged_today '
      'FROM prayers p '
      'WHERE p.user_id = ? AND p.deleted = 0 AND p.status = ? '
      'ORDER BY p.reminder_at IS NULL ASC, p.reminder_at ASC '
      'LIMIT ?',
      variables: [
        Variable.withString(today),
        Variable.withString(userId),
        Variable.withString('active'),
        Variable.withInt(_maxChecklistItems),
      ],
      readsFrom: {_db.prayers, _db.prayerLogs},
    ).get();

    final checklist = rows
        .map((r) => WatchPrayerItem(
              id: r.read<String>('id'),
              title: r.read<String>('title'),
              loggedToday: r.read<int>('logged_today') == 1,
            ))
        .toList();

    return WatchPayload(
      streakDays: streak.currentStreakDays,
      streakIncludesToday: streak.currentIncludesToday,
      prayerChecklist: checklist,
      versePreview: null,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
  }

  // Step 3 above swaps this for the WatchConnectivity write.
  Future<void> _send(WatchPayload payload) async {
    SyncLogger.debug(
      'WatchBridge: would send payload — streak=${payload.streakDays}, '
      'checklist=${payload.prayerChecklist.length}',
    );
  }

  static String _ymd(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
