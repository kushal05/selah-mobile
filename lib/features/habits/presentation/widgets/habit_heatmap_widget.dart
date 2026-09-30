import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../l10n/l10n.dart';
import '../../data/habit_log_repository.dart';
import '../../../../core/theme/theme_colors.dart';

/// A 3-month calendar heatmap showing daily habit completions.
///
/// Each cell is one day; filled cells indicate the habit was completed.
class HabitHeatmapWidget extends StatelessWidget {
  final HabitType habit;
  final Color color;
  /// Null when the history is not known — either still loading or failed.
  ///
  /// An empty set and a failed read drew the same empty grid, which reads as
  /// "you have never done this" — a claim about the user's history made from
  /// a query that never returned.
  final Set<int>? completedDays;

  /// Whether the read actually failed, as opposed to not having landed yet.
  ///
  /// Both arrive here as a null [completedDays], but they are not the same
  /// thing to say: every cold open passes through the loading state, and
  /// announcing "history unavailable" there is a false statement that then
  /// has to be taken back.
  final bool failed;

  const HabitHeatmapWidget({
    super.key,
    required this.habit,
    required this.color,
    required this.completedDays,
    this.failed = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Unknown history draws no cells: ninety-one empty squares is exactly what
    // a habit nobody has ever done looks like, and the read has not earned the
    // right to say that.
    //
    // The grid is still laid out, invisibly, so that the space it will occupy
    // is reserved. Replacing it with a line of text made the card sixty pixels
    // shorter, so every habit on the screen jumped when the read landed.
    //
    // Only a genuine failure gets a message. Loading gets silence, because the
    // loading state is not a failure and saying so is a claim that is about to
    // be retracted.
    if (completedDays == null) {
      return Stack(
        alignment: Alignment.center,
        children: [
          Opacity(
            opacity: 0,
            child: IgnorePointer(child: _grid(context, theme, const <int>{})),
          ),
          if (failed)
            Text(
              l10n(context).historyUnavailable,
              style:
                  theme.textTheme.bodySmall?.copyWith(color: context.mutedText),
            ),
        ],
      );
    }

    return _grid(context, theme, completedDays!);
  }

  Widget _grid(BuildContext context, ThemeData theme, Set<int> completedDays) {
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
                      fontSize: 12,
                      color: context.mutedText,
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
    return Container(
      width: 10,
      height: 10,
      margin: const EdgeInsets.all(1),
      decoration: BoxDecoration(
        color: done
            ? color.withValues(alpha: 0.85)
            // An empty cell is a ground, not a mark — subtleFill is the
            // token for exactly this.
            : context.subtleFill,
        borderRadius: BorderRadius.circular(AppTheme.radiusXS),
        border: isToday
            ? Border.all(color: color.withValues(alpha: 0.6), width: 1)
            : null,
      ),
    );
  }
}
