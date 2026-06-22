import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/sync/providers/sync_providers.dart';
import '../../../../core/theme/app_theme.dart';
import '../widgets/prayer_heatmap.dart';
import '../../../../shared/widgets/skeletons/skeletons.dart';

/// Prayer Analytics Dashboard with stat cards, heatmap, and top prayers.
class PrayerAnalyticsScreen extends ConsumerWidget {
  const PrayerAnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Prayer Analytics'),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(prayerCountsProvider);
          ref.invalidate(totalPrayerCountProvider);
          ref.invalidate(answeredPrayerCountProvider);
          ref.invalidate(answeredRatioProvider);
          ref.invalidate(prayerHeatmapProvider);
          ref.invalidate(prayerStreakProvider);
          ref.invalidate(frequentlyPrayedProvider);
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildStatCards(context, ref),
              const SizedBox(height: 24),
              _buildHeatmapSection(context, ref),
              const SizedBox(height: 24),
              _buildTopPrayersSection(context, ref),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatCards(BuildContext context, WidgetRef ref) {
    final totalAsync = ref.watch(totalPrayerCountProvider);
    final answeredAsync = ref.watch(answeredPrayerCountProvider);
    final ratioAsync = ref.watch(answeredRatioProvider);
    final streakAsync = ref.watch(prayerStreakProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Overview', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.5,
          children: [
            _StatCard(
              title: 'Total Prayers',
              value: totalAsync.whenOrNull(data: (v) => '$v') ?? '–',
              icon: Icons.format_list_bulleted_rounded,
              color: AppTheme.brandBlue,
            ),
            _StatCard(
              title: 'Answered',
              value: answeredAsync.whenOrNull(data: (v) => '$v') ?? '–',
              icon: Icons.check_circle_outline_rounded,
              color: AppTheme.teal,
            ),
            _StatCard(
              title: 'Answer Rate',
              value: ratioAsync.whenOrNull(
                      data: (v) => '${(v * 100).toStringAsFixed(0)}%') ??
                  '–',
              icon: Icons.pie_chart_outline_rounded,
              color: AppTheme.brandPurple,
            ),
            _StatCard(
              title: 'Day Streak',
              value: streakAsync.whenOrNull(data: (v) => '$v') ?? '–',
              icon: Icons.local_fire_department_rounded,
              color: AppTheme.coral,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildHeatmapSection(BuildContext context, WidgetRef ref) {
    final heatmapAsync = ref.watch(prayerHeatmapProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Prayer Activity', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        heatmapAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Column(children: [ListTileSkeleton(hasLeading: false), ListTileSkeleton(hasLeading: false), ListTileSkeleton(hasLeading: false)]),
          ),
          error: (_, _) => const SizedBox.shrink(),
          data: (heatmap) => PrayerHeatmap(data: heatmap),
        ),
      ],
    );
  }

  Widget _buildTopPrayersSection(BuildContext context, WidgetRef ref) {
    final topAsync = ref.watch(frequentlyPrayedProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Most Prayed',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        topAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 4),
            child: Column(children: [ListTileSkeleton(hasLeading: false), ListTileSkeleton(hasLeading: false)]),
          ),
          error: (_, _) => const SizedBox.shrink(),
          data: (items) {
            if (items.isEmpty) {
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.grey.shade400),
                    const SizedBox(width: 12),
                    Text(
                      'Start logging prayers to see stats',
                      style: TextStyle(
                        color: Colors.grey.shade500,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              );
            }

            return Column(
              children: items.asMap().entries.map((entry) {
                final index = entry.key;
                final item = entry.value;
                return _TopPrayerRow(
                  rank: index + 1,
                  title: item.title,
                  logCount: item.logCount,
                  onTap: () => context.push('/prayers/${item.prayerId}'),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }
}

// ==================== PRIVATE WIDGETS ====================

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final lightBg = Color.lerp(color, Colors.white, 0.93)!;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: lightBg,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color.withValues(alpha: 0.7)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: color.withValues(alpha: 0.7),
                  ),
                ),
              ),
            ],
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _TopPrayerRow extends StatelessWidget {
  final int rank;
  final String title;
  final int logCount;
  final VoidCallback? onTap;

  const _TopPrayerRow({
    required this.rank,
    required this.title,
    required this.logCount,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: AppTheme.brandPurple.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Text(
                  '$rank',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.brandPurple,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppTheme.teal.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '$logCount logs',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.teal,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
