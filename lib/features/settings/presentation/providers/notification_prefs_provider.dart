import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/sync/providers/sync_providers.dart';
import '../../data/services/notification_pref_api_service.dart';
import '../../domain/models/notification_preference.dart';

// ── Service provider ──────────────────────────────────────────────────────────

final notificationPrefApiServiceProvider =
    Provider<NotificationPrefApiService>((ref) {
  final config = ref.watch(syncConfigProvider);
  final interceptor = ref.watch(apiInterceptorProvider);
  final deviceId = ref.watch(deviceIdProvider);
  return NotificationPrefApiService(
    config: config,
    interceptor: interceptor,
    deviceId: deviceId,
  );
});

// ── Fetch provider ────────────────────────────────────────────────────────────

final notificationPrefsProvider =
    FutureProvider<List<NotificationPreference>>((ref) async {
  final service = ref.watch(notificationPrefApiServiceProvider);
  return service.getPreferences();
});

// ── Notifier ──────────────────────────────────────────────────────────────────

class NotifPrefNotifier
    extends AsyncNotifier<List<NotificationPreference>> {
  @override
  Future<List<NotificationPreference>> build() async {
    final service = ref.watch(notificationPrefApiServiceProvider);
    return service.getPreferences();
  }

  /// Toggle a preference's enabled flag and persist to the backend.
  Future<void> setEnabled(String category, {required bool enabled}) async {
    final current = state.valueOrNull;
    if (current == null) return;

    final updated = current
        .map((p) => p.category == category ? p.copyWith(enabled: enabled) : p)
        .toList();
    state = AsyncData(updated);

    await _save(updated);
  }

  /// Update the reminder time for a habit category and persist to the backend.
  Future<void> setReminderTime(String category, String? utcTime) async {
    final current = state.valueOrNull;
    if (current == null) return;

    final updated = current.map((p) {
      if (p.category != category) return p;
      return utcTime != null
          ? p.copyWith(reminderTime: utcTime)
          : p.copyWith(clearReminderTime: true);
    }).toList();
    state = AsyncData(updated);

    await _save(updated);
  }

  Future<void> _save(List<NotificationPreference> prefs) async {
    try {
      final service = ref.read(notificationPrefApiServiceProvider);
      await service.updatePreferences(prefs);
    } catch (e) {
      // Revert optimistic update on failure
      ref.invalidateSelf();
      rethrow;
    }
  }
}

final notifPrefNotifierProvider =
    AsyncNotifierProvider<NotifPrefNotifier, List<NotificationPreference>>(
        NotifPrefNotifier.new);
