import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/navigation/routes.dart';
import '../../../../core/sync/providers/sync_providers.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/habit_log_repository.dart';
import '../widgets/habit_reminder_tile.dart';
import '../widgets/habit_stats_card.dart';
import '../../../../core/theme/theme_colors.dart';
import '../../../../l10n/l10n.dart';
import '../../../../shared/widgets/section_label.dart';

/// Full-screen habit tracker — reachable from the "View All" button on the
/// Home screen's DailyHabitsWidget.
///
/// Shows per-habit cards (today's toggle, current + best streak, 7-day
/// weekly stats, 3-month heatmap), a Prayer Activity banner, and inline
/// daily reminder settings.
class HabitsScreen extends ConsumerWidget {
  const HabitsScreen({super.key});

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
    final prayerStreakAsync = ref.watch(prayerStreakProvider);
    final prayerStreak = prayerStreakAsync.valueOrNull ?? 0;

    return Scaffold(
      backgroundColor: context.pageGround,
      appBar: AppBar(
        title: Text(l10n(context).habits),
        backgroundColor: context.pageGround,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.only(
            top: AppTheme.spacing8, bottom: AppTheme.spacing32),
        children: [
          // ── Habit cards ──
          for (final habit in HabitType.values)
            HabitStatsCard(
              habit: habit,
              icon: _habitIcons[habit]!,
              color: _habitColors[habit]!,
            ),

          SectionLabel(l10n(context).prayer),
          _PrayerActivityBanner(
            streak: prayerStreak,
            onTap: () => context.push(Routes.prayerAnalytics),
          ),

          SectionLabel(l10n(context).reminders),
          const HabitReminderSection(),
        ],
      ),
    );
  }
}


class _PrayerActivityBanner extends StatelessWidget {
  final int streak;
  final VoidCallback onTap;

  const _PrayerActivityBanner({
    required this.streak,
    required this.onTap,
  });

  static const _color = AppTheme.brandPurple;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.spacing16, vertical: AppTheme.spacing6),
      child: ClipRRect(
        borderRadius: AppTheme.borderRadius3XL,
        child: Material(
          color: _color.withValues(alpha: 0.06),
          child: InkWell(
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.all(AppTheme.spacing14),
              decoration: BoxDecoration(
                borderRadius: AppTheme.borderRadius3XL,
                border: Border.all(color: _color.withValues(alpha: 0.18)),
              ),
              child: Row(
                children: [
                  Icon(Icons.insights_rounded, color: _color, size: 20),
                  const SizedBox(width: AppTheme.spacing12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n(context).prayerActivity,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: _color,
                            fontSize: 16,
                          ),
                        ),
                        if (streak > 0)
                          Text(
                            '$streak day streak',
                            style: TextStyle(
                              fontSize: 13,
                              color: _color.withValues(alpha: 0.7),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded,
                      color: _color.withValues(alpha: 0.6), size: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
