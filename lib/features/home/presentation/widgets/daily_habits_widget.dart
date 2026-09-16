import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/navigation/routes.dart';
import '../../../../core/theme/app_theme.dart';
import '../providers/habit_providers.dart';
import '../../../../l10n/l10n.dart';
import '../../../../core/theme/theme_colors.dart';

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
    // Nullable on purpose. `?? {}` rendered "nothing done yet" for three
    // different situations — loaded-and-empty, still loading, and failed to
    // load — and only one of those is true. The other two are a claim about
    // the user's day that we cannot make, and worse: toggleToday re-reads the
    // database rather than trusting this, so tapping a habit that is really
    // completed but drawn as not-done soft-deletes the completion. A tap
    // meant to record something destroys it.
    final completedKeys = todayAsync.valueOrNull;

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
              Semantics(
                button: true,
                child: GestureDetector(
                onTap: () => context.push(Routes.habits),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      l10n(context).viewAll,
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
              ),
            ],
          ),
        ),
        // A failed read leaves every tile inert, which on its own is a row of
        // controls that do nothing and say nothing. Name it, and offer the
        // retry — otherwise the fix above trades a destructive tap for a
        // silent one.
        if (todayAsync.hasError)
          Padding(
            padding: const EdgeInsets.only(bottom: AppTheme.spacing8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    l10n(context).habitsCouldntBeLoaded,
                    style: AppTheme.caption
                        .copyWith(color: context.dangerText),
                  ),
                ),
                TextButton(
                  onPressed: () => ref.invalidate(todayHabitKeysProvider),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(l10n(context).retry),
                ),
              ],
            ),
          ),
        Row(
          children: _habits.map((habit) {
            // null = we do not know yet, which is not the same as "no".
            final isDone = completedKeys?.contains(habit.key);
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

  /// Whether the habit is done today, or null while that is unknown.
  final bool? isDone;
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

    final known = isDone != null;
    // Styling decisions take the "not done" look while unknown — the tile is
    // inert then, so it cannot mislead a tap; only the status glyph below
    // distinguishes the two, by declining to show either mark.
    final done = isDone == true;

    return Semantics(
      button: known,
      // Never announce a state we do not have. Saying "not done, mark done"
      // while the read is still in flight invites exactly the tap that
      // destroys the completion.
      label: known
          ? (isDone!
              ? '${habit.label}, done today. Mark not done'
              : '${habit.label}, not done. Mark done')
          : '${habit.label}, loading',
      child: GestureDetector(
      // Inert until the state is known, for the same reason.
      onTap: !known
          ? null
          : () async {
        final messenger = ScaffoldMessenger.of(context);
        final failed = l10n(context).habitCouldntBeUpdated;
        try {
          await ref.read(habitLogRepositoryProvider).toggleToday(habit);
          // todayHabitKeysProvider is a StreamProvider with readsFrom:{habitLogs}
          // and updates automatically on DB write — no invalidate needed.
          // Streak is a FutureProvider so must be explicitly refreshed.
          ref.invalidate(habitStreakProvider(habit));
        } catch (_) {
          // Say so. Swallowing this left the tile unchanged with no
          // explanation, which reads as a tap that missed — so the user taps
          // again, against a write that is failing.
          messenger.showSnackBar(SnackBar(
            content: Text(failed),
            behavior: SnackBarBehavior.floating,
          ));
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.spacing12,
          vertical: AppTheme.spacing12,
        ),
        decoration: BoxDecoration(
          color: done
              ? color.withValues(alpha: 0.12)
              : theme.colorScheme.surfaceContainerHigh,
          borderRadius: AppTheme.borderRadiusLG,
          border: Border.all(
            color: done ? color.withValues(alpha: 0.4) : Colors.transparent,
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
                  color: done ? color : context.mutedText,
                ),
                const Spacer(),
                // Three states, not two: neither mark is shown until we know
                // which is true.
                if (!known)
                  Icon(Icons.more_horiz_rounded,
                      size: 16, color: context.decorativeInk)
                else if (done)
                  Icon(Icons.check_circle_rounded, size: 16, color: color)
                else
                  Icon(Icons.radio_button_unchecked_rounded,
                      size: 16,
                      color: context.mutedText),
              ],
            ),
            const SizedBox(height: AppTheme.spacing8),
            Text(
              habit.label,
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: done
                    ? color.withValues(alpha: 0.9)
                    : context.mutedText,
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
                        : context.mutedText),
                const SizedBox(width: 2),
                Text(
                  streak > 0 ? '$streak day${streak == 1 ? '' : 's'}' : '—',
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontSize: 12,
                    color: streak > 0
                        ? const Color(0xFFEF4444)
                        : context.mutedText,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
    );
  }
}
