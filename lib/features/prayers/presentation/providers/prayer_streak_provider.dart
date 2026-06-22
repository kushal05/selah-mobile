import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/sync/providers/sync_providers.dart';
import '../../data/services/prayer_streak_service.dart';
import '../../domain/models/prayer_streak.dart';

final prayerStreakServiceProvider = Provider<PrayerStreakService>((ref) {
  final db = ref.watch(syncDatabaseProvider);
  return PrayerStreakService(db);
});

/// Current prayer streak for the signed-in user. Invalidate after logging a
/// prayer if you need an immediate refresh; the underlying stream watch on
/// prayer_logs is left to the consuming screen.
final prayerStreakProvider = FutureProvider<PrayerStreak>((ref) async {
  final userId = ref.watch(currentUserIdProvider);
  final service = ref.watch(prayerStreakServiceProvider);
  return service.compute(userId: userId);
});
