import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/domain/enums/prayer_enums.dart';
import '../../../../core/sync/providers/sync_providers.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/cards/overview_card.dart';
import '../../../notes/presentation/providers/database_provider.dart';

/// Displays overview cards in a grid on the home dashboard
class OverviewGrid extends ConsumerWidget {
  const OverviewGrid({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shell = StatefulNavigationShell.of(context);

    // Watch only counts via .select() to avoid rebuilding on every entity change
    final activePrayersCount = ref.watch(prayersStreamProvider.select(
      (async) => async.valueOrNull
          ?.where((p) => p.status == PrayerStatus.active)
          .length ?? 0,
    ));

    final notesCount = ref.watch(notesStreamProvider.select(
      (async) => async.valueOrNull?.length ?? 0,
    ));

    final promisesCount = ref.watch(promisesStreamProvider.select(
      (async) => async.valueOrNull?.length ?? 0,
    ));

    final peopleCount = ref.watch(peopleStreamProvider.select(
      (async) => async.valueOrNull?.length ?? 0,
    ));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 4,
              height: 20,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 8),
            Text('Overview', style: Theme.of(context).textTheme.titleMedium),
          ],
        ),
        const SizedBox(height: 16),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          childAspectRatio: 1.3,
          children: [
            OverviewCard(
              title: 'Active Prayers',
              count: activePrayersCount.toString(),
              icon: Icons.favorite,
              color: AppTheme.brandBlue,
              onTap: () => shell.goBranch(2), // Prayers tab
            ),
            OverviewCard(
              title: 'Recent Notes',
              count: notesCount.toString(),
              icon: Icons.description,
              color: AppTheme.brandPurple,
              onTap: () => shell.goBranch(1), // Notes tab
            ),
            OverviewCard(
              title: 'Promises',
              count: promisesCount.toString(),
              icon: Icons.bookmark,
              color: AppTheme.rosePink,
              onTap: () => shell.goBranch(4), // Promises tab
            ),
            OverviewCard(
              title: 'People',
              count: peopleCount.toString(),
              icon: Icons.people,
              color: AppTheme.teal,
              onTap: () => shell.goBranch(6), // People tab
            ),
          ],
        ),
      ],
    );
  }
}
