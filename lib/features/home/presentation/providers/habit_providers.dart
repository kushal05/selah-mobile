import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/sync/providers/sync_providers.dart';
import '../../../habits/data/habit_log_repository.dart';

export '../../../habits/data/habit_log_repository.dart' show HabitType, toDateDay;

/// Habit log repository — sync-enabled daily check-ins.
final habitLogRepositoryProvider = Provider<HabitLogRepository>((ref) {
  final db = ref.watch(syncDatabaseProvider);
  final userId = ref.watch(currentUserIdProvider);
  final deviceId = ref.watch(deviceIdProvider);
  return HabitLogRepository(db, userId, deviceId);
});

/// Set of habit keys completed today (reactive stream).
final todayHabitKeysProvider = StreamProvider<Set<String>>((ref) {
  return ref.watch(habitLogRepositoryProvider).watchTodayCompletedKeys();
});

/// Current streak for a given [HabitType].
final habitStreakProvider =
    FutureProvider.family<int, HabitType>((ref, habit) {
  return ref.watch(habitLogRepositoryProvider).getStreak(habit);
});
