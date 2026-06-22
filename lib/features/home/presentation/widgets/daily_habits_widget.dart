import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/navigation/routes.dart';
import '../../../../core/theme/app_theme.dart';
import '../providers/habit_providers.dart';

/// Home-screen card showing today's three habit check-ins with streak counts.
class DailyHabitsWidget extends ConsumerWidget {
  const DailyHabitsWidget({super.key});

  static const _habits = HabitType.values;

  static const _habitIcons = {
    HabitType.bible: Icons.menu_book_rounded,
    HabitType.meditation: Icons.self_improvement_rounded,
  };

  static const _habitColors = {
    HabitType.bible: Color(0xFF10B981),
    HabitType.meditation: Color(0xFF8B5CF6),
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final todayAsync = ref.watch(todayHabitKeysProvider);
    final completedKeys = todayAsync.valueOrNull ?? {};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: AppTheme.spacing12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Today\'s Habits',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
                  ),
                ),
              ),
              GestureDetector(
                onTap: () => context.push(Routes.habits),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'View All',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 2),
                    Icon(Icons.chevron_right_rounded,
                        size: 16, color: theme.colorScheme.primary),
                  ],
                ),
              ),
            ],
          ),
        ),
        Row(
          children: _habits.map((habit) {
            final isDone = completedKeys.contains(habit.key);
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  right: habit != _habits.last ? AppTheme.spacing8 : 0,
                ),
                child: _HabitTile(
                  habit: habit,
                  isDone: isDone,
                  icon: _habitIcons[habit]!,
                  color: _habitColors[habit]!,
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

class _HabitTile extends ConsumerWidget {
  final HabitType habit;
  final bool isDone;
  final IconData icon;
  final Color color;

  const _HabitTile({
    required this.habit,
    required this.isDone,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final streakAsync = ref.watch(habitStreakProvider(habit));
    final streak = streakAsync.valueOrNull ?? 0;

    return GestureDetector(
      onTap: () async {
        try {
          await ref.read(habitLogRepositoryProvider).toggleToday(habit);
          // todayHabitKeysProvider is a StreamProvider with readsFrom:{habitLogs}
          // and updates automatically on DB write — no invalidate needed.
          // Streak is a FutureProvider so must be explicitly refreshed.
          ref.invalidate(habitStreakProvider(habit));
        } catch (_) {
          // Best-effort — streak/check state will remain unchanged on failure
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.spacing12,
          vertical: AppTheme.spacing12,
        ),
        decoration: BoxDecoration(
          color: isDone
              ? color.withValues(alpha: 0.12)
              : theme.colorScheme.surfaceContainerHigh,
          borderRadius: AppTheme.borderRadiusLG,
          border: Border.all(
            color: isDone ? color.withValues(alpha: 0.4) : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: isDone ? color : theme.colorScheme.onSurface.withValues(alpha: 0.4),
                ),
                const Spacer(),
                if (isDone)
                  Icon(Icons.check_circle_rounded, size: 16, color: color)
                else
                  Icon(Icons.radio_button_unchecked_rounded,
                      size: 16,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.25)),
              ],
            ),
            const SizedBox(height: AppTheme.spacing8),
            Text(
              habit.label,
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: isDone
                    ? color.withValues(alpha: 0.9)
                    : theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                Icon(Icons.local_fire_department_rounded,
                    size: 11,
                    color: streak > 0
                        ? const Color(0xFFEF4444)
                        : theme.colorScheme.onSurface.withValues(alpha: 0.25)),
                const SizedBox(width: 2),
                Text(
                  streak > 0 ? '$streak day${streak == 1 ? '' : 's'}' : '—',
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontSize: 10,
                    color: streak > 0
                        ? const Color(0xFFEF4444)
                        : theme.colorScheme.onSurface.withValues(alpha: 0.3),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
