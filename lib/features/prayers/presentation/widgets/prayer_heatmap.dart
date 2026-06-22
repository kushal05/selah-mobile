import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

/// GitHub-style heatmap calendar grid showing prayer activity.
/// Each cell represents a day; intensity reflects the log count.
class PrayerHeatmap extends StatelessWidget {
  final Map<DateTime, int> data;
  final int weeks;

  /// Cell size including margin (12px cell + 2px margin = 14px total).
  static const double _cellTotal = 14;

  const PrayerHeatmap({
    super.key,
    required this.data,
    this.weeks = 20,
  });

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);

    // Find the Monday of the week containing the start date
    final startDate = todayDate.subtract(Duration(days: (weeks * 7) - 1));
    final mondayOffset = startDate.weekday - 1; // Monday = 1
    final gridStart = startDate.subtract(Duration(days: mondayOffset));

    // Compute max for color scaling
    final maxCount =
        data.values.isEmpty ? 1 : data.values.reduce((a, b) => a > b ? a : b);

    final totalDays = weeks * 7 + mondayOffset;
    final weekCount = (totalDays / 7).ceil();

    return Container(
      padding: AppTheme.paddingAllMD,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: AppTheme.borderRadiusXL,
        border: Border.all(color: AppTheme.gray200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Day-of-week labels (fixed column)
              Padding(
                padding: const EdgeInsets.only(top: AppTheme.spacing16),
                child: _buildDayLabels(context),
              ),
              const SizedBox(width: AppTheme.spacing4),
              // Month labels + grid scroll together
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  reverse: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildMonthLabels(gridStart, weekCount),
                      const SizedBox(height: AppTheme.spacing2),
                      _buildGrid(
                        gridStart: gridStart,
                        todayDate: todayDate,
                        weekCount: weekCount,
                        maxCount: maxCount,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.spacing8),
          _buildLegend(context),
        ],
      ),
    );
  }

  Widget _buildMonthLabels(DateTime gridStart, int weekCount) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];

    final labels = <Widget>[];
    int? lastMonth;

    for (int w = 0; w < weekCount; w++) {
      final weekStart = gridStart.add(Duration(days: w * 7));
      if (weekStart.month != lastMonth) {
        lastMonth = weekStart.month;
        labels.add(
          SizedBox(
            width: _cellTotal,
            child: Text(
              months[weekStart.month - 1],
              style: TextStyle(fontSize: 9, color: AppTheme.gray500),
              overflow: TextOverflow.visible,
              softWrap: false,
            ),
          ),
        );
      } else {
        labels.add(const SizedBox(width: _cellTotal));
      }
    }

    return SizedBox(
      height: 14,
      child: Row(children: labels),
    );
  }

  Widget _buildDayLabels(BuildContext context) {
    const labels = ['', 'M', '', 'W', '', 'F', ''];
    return Column(
      children: labels
          .map((l) => SizedBox(
                height: _cellTotal,
                child: Center(
                  child: Text(
                    l,
                    style:
                        TextStyle(fontSize: 9, color: AppTheme.gray500),
                  ),
                ),
              ))
          .toList(),
    );
  }

  Widget _buildGrid({
    required DateTime gridStart,
    required DateTime todayDate,
    required int weekCount,
    required int maxCount,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: List.generate(weekCount, (w) {
        return Column(
          children: List.generate(7, (d) {
            final date = gridStart.add(Duration(days: w * 7 + d));
            final dateKey = DateTime(date.year, date.month, date.day);

            if (dateKey.isAfter(todayDate)) {
              return const SizedBox(width: _cellTotal, height: _cellTotal);
            }

            final count = data[dateKey] ?? 0;
            final intensity =
                maxCount > 0 ? (count / maxCount).clamp(0.0, 1.0) : 0.0;

            return Tooltip(
              message:
                  '${dateKey.day}/${dateKey.month}: $count prayer${count == 1 ? '' : 's'}',
              child: Container(
                width: 12,
                height: 12,
                margin: const EdgeInsets.all(1),
                decoration: BoxDecoration(
                  color: _colorForIntensity(intensity),
                  borderRadius: BorderRadius.circular(AppTheme.spacing2),
                ),
              ),
            );
          }),
        );
      }),
    );
  }

  Widget _buildLegend(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text(
          'Less',
          style: TextStyle(fontSize: 9, color: AppTheme.gray500),
        ),
        const SizedBox(width: AppTheme.spacing4),
        for (final intensity in [0.0, 0.25, 0.5, 0.75, 1.0])
          Container(
            width: 10,
            height: 10,
            margin: const EdgeInsets.symmetric(horizontal: 1),
            decoration: BoxDecoration(
              color: _colorForIntensity(intensity),
              borderRadius: BorderRadius.circular(AppTheme.spacing2),
            ),
          ),
        const SizedBox(width: AppTheme.spacing4),
        Text(
          'More',
          style: TextStyle(fontSize: 9, color: AppTheme.gray500),
        ),
      ],
    );
  }

  Color _colorForIntensity(double intensity) {
    if (intensity <= 0) return AppTheme.prayerHeatmapEmpty;
    if (intensity <= 0.25) return AppTheme.brandPurple.withValues(alpha: 0.25);
    if (intensity <= 0.50) return AppTheme.brandPurple.withValues(alpha: 0.50);
    if (intensity <= 0.75) return AppTheme.brandPurple.withValues(alpha: 0.75);
    return AppTheme.brandPurple;
  }
}
