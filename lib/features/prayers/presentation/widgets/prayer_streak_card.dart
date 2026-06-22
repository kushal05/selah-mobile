import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/prayer_streak.dart';
import '../providers/prayer_streak_provider.dart';

/// Compact card showing current streak, longest streak, and a 12-week
/// heatmap of prayer-log activity. Designed to slot into the prayers
/// dashboard or home dashboard.
class PrayerStreakCard extends ConsumerWidget {
  const PrayerStreakCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final streakAsync = ref.watch(prayerStreakProvider);

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: streakAsync.when(
          loading: () => const SizedBox(
            height: 96,
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (_, _) => const SizedBox(
            height: 96,
            child: Center(child: Text('Streak unavailable')),
          ),
          data: (s) => _StreakBody(streak: s),
        ),
      ),
    );
  }
}

class _StreakBody extends StatelessWidget {
  final PrayerStreak streak;
  const _StreakBody({required this.streak});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final streakColor = streak.currentIncludesToday
        ? theme.colorScheme.primary
        : theme.colorScheme.tertiary;
    final streakLabel = streak.currentStreakDays == 0
        ? 'No active streak'
        : streak.currentIncludesToday
            ? 'Day streak'
            : 'Day streak (log today to keep it)';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.local_fire_department, color: streakColor),
            const SizedBox(width: 8),
            Text(
              'Prayer Streak',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '${streak.currentStreakDays}',
              style: theme.textTheme.displaySmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: streakColor,
                height: 1,
              ),
            ),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                streakLabel,
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _MiniStat(
              label: 'Longest',
              value: '${streak.longestStreakDays}d',
            ),
            const SizedBox(width: 16),
            _MiniStat(
              label: 'Total days',
              value: '${streak.totalActiveDays}',
            ),
          ],
        ),
        const SizedBox(height: 16),
        _Heatmap(streak: streak),
      ],
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  const _MiniStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
      ],
    );
  }
}

/// Grid: rows = weekdays (Mon..Sun), columns = weeks. Newest week on the
/// right. Each cell is colored if there was a prayer log that day.
class _Heatmap extends StatelessWidget {
  final PrayerStreak streak;
  const _Heatmap({required this.streak});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final windowDays = streak.heatmapWindowDays;
    final start = today.subtract(Duration(days: windowDays - 1));

    // Align start to the Monday on/before [start] so each column is a
    // consistent Mon..Sun week.
    final startOfWeek = start.subtract(Duration(days: (start.weekday - 1) % 7));
    final totalCells = today.difference(startOfWeek).inDays + 1;
    final columns = (totalCells / 7).ceil();

    final activeColor = theme.colorScheme.primary;
    final dimColor = theme.colorScheme.primary.withValues(alpha: 0.15);
    final emptyColor =
        theme.colorScheme.onSurface.withValues(alpha: 0.06);

    return LayoutBuilder(
      builder: (context, constraints) {
        final cell = ((constraints.maxWidth - (columns - 1) * 3) / columns)
            .clamp(8.0, 16.0);
        return SizedBox(
          height: cell * 7 + 6 * 3,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: List.generate(columns, (col) {
              return Padding(
                padding: EdgeInsets.only(right: col == columns - 1 ? 0 : 3),
                child: Column(
                  children: List.generate(7, (row) {
                    final cellDate =
                        startOfWeek.add(Duration(days: col * 7 + row));
                    final inFuture = cellDate.isAfter(today);
                    final inPast = cellDate.isBefore(start);
                    final ymd = _ymd(cellDate);
                    final hasLog = streak.activeDates.contains(ymd);
                    Color color;
                    if (inFuture || inPast) {
                      color = Colors.transparent;
                    } else if (hasLog) {
                      // Brighter for the most-recent week.
                      final daysAgo = today.difference(cellDate).inDays;
                      color = daysAgo < 7 ? activeColor : dimColor;
                    } else {
                      color = emptyColor;
                    }
                    return Padding(
                      padding: EdgeInsets.only(bottom: row == 6 ? 0 : 3),
                      child: Container(
                        width: cell,
                        height: cell,
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    );
                  }),
                ),
              );
            }),
          ),
        );
      },
    );
  }

  static String _ymd(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
