import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/sync/utils/sync_logger.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../features/home/presentation/providers/habit_providers.dart';
import '../providers/habit_analytics_providers.dart';
import 'habit_heatmap_widget.dart';
import '../../../../core/providers/motion_preferences.dart';
import '../../../../core/theme/theme_colors.dart';
import '../../../../l10n/l10n.dart';

/// Per-habit card showing today's toggle, current streak, best streak,
/// weekly stats, and a 3-month heatmap calendar.
class HabitStatsCard extends ConsumerWidget {
  final HabitType habit;
  final IconData icon;
  final Color color;

  const HabitStatsCard({
    super.key,
    required this.habit,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final todayAsync = ref.watch(todayHabitKeysProvider);
    final streakAsync = ref.watch(habitStreakProvider(habit));
    final bestAsync = ref.watch(habitBestStreakProvider(habit));
    final weekAsync = ref.watch(habitWeeklyStatsProvider(habit));
    final historyAsync = ref.watch(habitHistoryProvider(habit));

    // Nullable: `?? false` made "not read yet" look like "not done", and
    // toggleToday re-queries the database rather than trusting this — so a
    // tap in that window finds the existing log and deletes it. Same bug as
    // the home screen's habits row; this card is the other place it lives.
    final done = todayAsync.valueOrNull?.contains(habit.key);
    final isDone = done == true;
    final known = done != null;
    final streak = streakAsync.valueOrNull ?? 0;
    final best = bestAsync.valueOrNull ?? 0;
    final week = weekAsync.valueOrNull ?? List.filled(7, false);
    final history = historyAsync.valueOrNull ?? {};

    return Container(
      margin: const EdgeInsets.symmetric(
          horizontal: AppTheme.spacing16, vertical: AppTheme.spacing6),
      decoration: BoxDecoration(
        color: context.cardSurface,
        borderRadius: AppTheme.borderRadius3XL,
        border: Border.all(
          color: isDone
              ? color.withValues(alpha: 0.3)
              : context.hairline,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spacing16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: isDone
                        ? color.withValues(alpha: 0.15)
                        : theme.colorScheme.surfaceContainerHigh,
                    borderRadius: AppTheme.borderRadiusLG,
                  ),
                  child: Icon(icon, size: 18,
                      color: isDone
                          ? color
                          : context.mutedText),
                ),
                const SizedBox(width: AppTheme.spacing12),
                Expanded(
                  child: Text(
                    habit.label,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                Semantics(
                  button: known,
                  label: known
                      ? (isDone
                          ? '${habit.label}, done today. Mark not done'
                          : '${habit.label}, not done. Mark done')
                      : '${habit.label}, loading',
                  child: GestureDetector(
                  onTap: !known
                      ? null
                      : () async {
                    final messenger = ScaffoldMessenger.of(context);
                    final failed = l10n(context).habitCouldntBeUpdated;
                    try {
                      await ref
                          .read(habitLogRepositoryProvider)
                          .toggleToday(habit);
                      ref.invalidate(habitStreakProvider(habit));
                      ref.invalidate(habitBestStreakProvider(habit));
                      ref.invalidate(habitHistoryProvider(habit));
                      ref.invalidate(habitWeeklyStatsProvider(habit));
                    } catch (e) {
                      SyncLogger.error('[HabitStatsCard] toggleToday failed', e);
                      // The log is for us. Tell the user too — otherwise the
                      // chip just does not change and reads as a missed tap.
                      messenger.showSnackBar(SnackBar(
                        content: Text(failed),
                        behavior: SnackBarBehavior.floating,
                      ));
                    }
                  },
                  child: AnimatedContainer(
                    duration: context.motion(const Duration(milliseconds: 200)),
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppTheme.spacing12,
                        vertical: AppTheme.spacing6),
                    decoration: BoxDecoration(
                      color: isDone
                          ? color.withValues(alpha: 0.12)
                          : theme.colorScheme.surfaceContainerHigh,
                      borderRadius: AppTheme.borderRadiusFull,
                      border: Border.all(
                        color: isDone
                            ? color.withValues(alpha: 0.4)
                            : Colors.transparent,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          !known
                              ? Icons.more_horiz_rounded
                              : isDone
                                  ? Icons.check_circle_rounded
                                  : Icons.radio_button_unchecked_rounded,
                          size: 14,
                          color: isDone ? color : context.mutedText,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          !known
                              ? '\u2026'
                              : isDone
                                  ? 'Done'
                                  : 'Mark done',
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: isDone
                                ? color
                                : theme.colorScheme.onSurface
                                    .withValues(alpha: 0.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                ),
              ],
            ),

            const SizedBox(height: AppTheme.spacing16),

            Row(
              children: [
                _StatChip(
                  icon: Icons.local_fire_department_rounded,
                  iconColor: streak > 0
                      ? const Color(0xFFEF4444)
                      : context.mutedText,
                  label: streak > 0
                      ? '$streak day${streak == 1 ? '' : 's'}'
                      : '0 days',
                  sublabel: l10n(context).currentStreak,
                  theme: theme,
                ),
                const SizedBox(width: AppTheme.spacing8),
                _StatChip(
                  icon: Icons.emoji_events_rounded,
                  iconColor: best > 0
                      ? const Color(0xFFF59E0B)
                      : context.mutedText,
                  label: best > 0 ? '$best day${best == 1 ? '' : 's'}' : '—',
                  sublabel: l10n(context).bestStreak,
                  theme: theme,
                ),
              ],
            ),

            const SizedBox(height: AppTheme.spacing16),

            _WeekRow(week: week, color: color, theme: theme),

            const SizedBox(height: AppTheme.spacing16),

            HabitHeatmapWidget(
              habit: habit,
              color: color,
              completedDays: history,
            ),
          ],
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String sublabel;
  final ThemeData theme;

  const _StatChip({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.sublabel,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: AppTheme.spacing12, vertical: AppTheme.spacing8),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHigh,
          borderRadius: AppTheme.borderRadiusLG,
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: iconColor),
            const SizedBox(width: AppTheme.spacing6),
            // Flexible, and the labels ellipsise: the Column had no bound, so
            // a long streak label pushed this Row 44px past its half of the
            // card. Found by the first run of the screen smoke tests.
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  Text(sublabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontSize: 12,
                        color:
                            context.mutedText,
                      )),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WeekRow extends StatelessWidget {
  final List<bool> week;
  final Color color;
  final ThemeData theme;

  const _WeekRow({
    required this.week,
    required this.color,
    required this.theme,
  });

  static const _days = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final todayIndex = now.weekday - 1; // 0 = Monday

    return Row(
      children: List.generate(7, (i) {
        final done = i < week.length && week[i];
        final isToday = i == todayIndex;
        final isFuture = i > todayIndex;

        return Expanded(
          child: Column(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: done
                      ? color.withValues(alpha: 0.85)
                      : isFuture
                          ? Colors.transparent
                          : theme.colorScheme.onSurface
                              .withValues(alpha: 0.07),
                  border: isToday && !done
                      ? Border.all(
                          color: color.withValues(alpha: 0.4), width: 1.5)
                      : null,
                ),
                child: done
                    ? Icon(Icons.check_rounded,
                        size: 14, color: Colors.white)
                    : null,
              ),
              const SizedBox(height: 4),
              Text(
                _days[i],
                style: theme.textTheme.labelSmall?.copyWith(
                  fontSize: 12,
                  fontWeight:
                      isToday ? FontWeight.w700 : FontWeight.normal,
                  color: isToday
                      ? color
                      : theme.colorScheme.onSurface
                          .withValues(alpha: isFuture ? 0.25 : 0.5),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}
