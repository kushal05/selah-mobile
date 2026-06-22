import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../features/home/presentation/providers/habit_providers.dart';

/// Per-habit completion history — Set of dateDay values (UTC midnight ms)
/// for the past 3 months. Used to render the streak calendar heatmap.
final habitHistoryProvider =
    FutureProvider.family<Set<int>, HabitType>((ref, habit) {
  return ref.watch(habitLogRepositoryProvider).getHistory(habit);
});

/// All-time best streak for a given [HabitType].
final habitBestStreakProvider =
    FutureProvider.family<int, HabitType>((ref, habit) {
  return ref.watch(habitLogRepositoryProvider).getBestStreak(habit);
});

/// Weekly stats (Mon–Sun) for a given [HabitType].
/// Returns a 7-element list of booleans.
final habitWeeklyStatsProvider =
    FutureProvider.family<List<bool>, HabitType>((ref, habit) {
  return ref.watch(habitLogRepositoryProvider).getWeeklyStats(habit);
});
