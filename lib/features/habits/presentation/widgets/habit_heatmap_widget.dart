import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../data/habit_log_repository.dart';

/// A 3-month calendar heatmap showing daily habit completions.
///
/// Each cell is one day; filled cells indicate the habit was completed.
class HabitHeatmapWidget extends StatelessWidget {
  final HabitType habit;
  final Color color;
  final Set<int> completedDays;

  const HabitHeatmapWidget({
    super.key,
    required this.habit,
    required this.color,
    required this.completedDays,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final today = toDateDay(DateTime.now());

    final cells = List.generate(91, (i) {
      final dayMs = today - (90 - i) * msPerDay;
      final done = completedDays.contains(dayMs);
      final isToday = dayMs == today;
      return _DayCell(done: done, color: color, isToday: isToday);
    });

    // Group into 13 columns of 7 rows (week columns)
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Weekday row labels
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: ['M', 'T', 'W', 'T', 'F', 'S', 'S']
              .map(
                (d) => SizedBox(
                  width: 12,
                  child: Text(
                    d,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontSize: 8,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.35),
                    ),
                  ),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 3),
        // Week columns
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: List.generate(13, (col) {
            return Column(
              children: List.generate(7, (row) {
                final idx = col * 7 + row;
                if (idx >= cells.length) {
                  return const SizedBox(width: 12, height: 12);
                }
                return cells[idx];
              }),
            );
          }),
        ),
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  final bool done;
  final Color color;
  final bool isToday;

  const _DayCell({
    required this.done,
    required this.color,
    required this.isToday,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 10,
      height: 10,
      margin: const EdgeInsets.all(1),
      decoration: BoxDecoration(
        color: done
            ? color.withValues(alpha: 0.85)
            : theme.colorScheme.onSurface.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(AppTheme.radiusXS),
        border: isToday
            ? Border.all(color: color.withValues(alpha: 0.6), width: 1)
            : null,
      ),
    );
  }
}
