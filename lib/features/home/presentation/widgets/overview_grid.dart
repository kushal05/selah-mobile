import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/sync/providers/sync_providers.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/cards/overview_card.dart';
import '../../../../l10n/l10n.dart';
import '../../../../core/navigation/tab_navigation.dart';

/// Displays overview cards in a grid on the home dashboard
class OverviewGrid extends ConsumerWidget {
  const OverviewGrid({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {

    // COUNT(*) providers rather than the full entity streams. `.select()` kept
    // this widget from rebuilding, but the watches underneath still decoded
    // every note, prayer, promise and person into a model on each change just
    // to produce four numbers.
    final activePrayersCount =
        ref.watch(activePrayerCountProvider).valueOrNull ?? 0;
    final notesCount = ref.watch(noteCountProvider).valueOrNull ?? 0;
    final promisesCount = ref.watch(promiseCountProvider).valueOrNull ?? 0;
    final peopleCount = ref.watch(personCountProvider).valueOrNull ?? 0;

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
            Text(l10n(context).overview, style: Theme.of(context).textTheme.titleMedium),
          ],
        ),
        const SizedBox(height: 16),
        // Laid out as rows of IntrinsicHeight rather than a GridView with a
        // fixed childAspectRatio: a fixed ratio cannot grow when its text
        // does, so a longer title or a larger text scale overflows the card.
        // IntrinsicHeight keeps the two cards in a row equal while letting
        // the row take the height its content needs.
        _OverviewRows(
          children: [
            OverviewCard(
              title: l10n(context).activePrayers,
              count: activePrayersCount.toString(),
              icon: Icons.favorite,
              color: AppTheme.brandBlue,
              onTap: () => goToTab(context, 2), // Prayers tab
            ),
            OverviewCard(
              title: l10n(context).recentNotes,
              count: notesCount.toString(),
              icon: Icons.description,
              color: AppTheme.brandPurple,
              onTap: () => goToTab(context, 1), // Notes tab
            ),
            OverviewCard(
              title: l10n(context).navPromises,
              count: promisesCount.toString(),
              icon: Icons.bookmark,
              color: AppTheme.rosePink,
              onTap: () => goToTab(context, 4), // Promises tab
            ),
            OverviewCard(
              title: l10n(context).people,
              count: peopleCount.toString(),
              icon: Icons.people,
              color: AppTheme.teal,
              onTap: () => goToTab(context, 6), // People tab
            ),
          ],
        ),
      ],
    );
  }
}

/// Two-column layout whose rows size to their content.
///
/// Replaces `GridView.count(childAspectRatio: ...)`, which clips as soon as a
/// title wraps or the user raises their text size.
class _OverviewRows extends StatelessWidget {
  final List<Widget> children;
  const _OverviewRows({required this.children});

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i += 2) {
      final left = children[i];
      final right = i + 1 < children.length ? children[i + 1] : null;
      if (rows.isNotEmpty) rows.add(const SizedBox(height: 16));
      rows.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: left),
              const SizedBox(width: 16),
              // An odd count keeps the last card at one column width rather
              // than stretching it across the row.
              Expanded(child: right ?? const SizedBox.shrink()),
            ],
          ),
        ),
      );
    }
    return Column(children: rows);
  }
}
