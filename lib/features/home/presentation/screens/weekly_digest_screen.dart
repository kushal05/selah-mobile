import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/weekly_digest.dart';
import '../providers/weekly_digest_provider.dart';
import '../../../../l10n/l10n.dart';
import '../../../../shared/widgets/error_state.dart';
import '../../../../shared/utils/date_format.dart';

/// Shows a 7-day summary of user activity (prayers, notes, Bible, people).
/// Read-only — purely derived from existing data, so no writes / oplog.
class WeeklyDigestScreen extends ConsumerWidget {
  const WeeklyDigestScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final digestAsync = ref.watch(weeklyDigestProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n(context).thisWeek),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: l10n(context).refresh,
            onPressed: () => ref.invalidate(weeklyDigestProvider),
          ),
        ],
      ),
      body: digestAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorState(
          error: e,
          onRetry: () => ref.invalidate(weeklyDigestProvider),
        ),
        data: (d) => d.isEmpty ? const _EmptyState() : _DigestBody(digest: d),
      ),
    );
  }
}

class _DigestBody extends StatelessWidget {
  final WeeklyDigest digest;
  const _DigestBody({required this.digest});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return RefreshIndicator(
      onRefresh: () async {},
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            _formatRange(digest.windowStart, digest.windowEnd),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 16),
          _StatGrid(digest: digest),
          const SizedBox(height: 16),
          if (digest.topPrayerTitles.isNotEmpty)
            _TopList(
              title: l10n(context).mostPrayed2,
              icon: Icons.volunteer_activism_outlined,
              entries: digest.topPrayerTitles,
            ),
          if (digest.topChapters.isNotEmpty) ...[
            const SizedBox(height: 12),
            _TopList(
              title: l10n(context).mostOpenedChapters,
              icon: Icons.menu_book_outlined,
              entries: digest.topChapters,
            ),
          ],
          const SizedBox(height: 24),
          Center(
            child: Text(
              l10n(context).pulledFromYourLocalActivityNothingLeavesTheD,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatRange(DateTime start, DateTime end) {
    String fmt(DateTime d) => formatShortDate(d);
    return '${fmt(start)} — ${fmt(end)}';
  }
}

class _StatGrid extends StatelessWidget {
  final WeeklyDigest digest;
  const _StatGrid({required this.digest});

  @override
  Widget build(BuildContext context) {
    final tiles = <_StatTile>[
      _StatTile(
        icon: Icons.volunteer_activism_outlined,
        label: l10n(context).prayersLogged,
        value: '${digest.prayersLogged}',
        sub: '${digest.prayerDaysActive} of ${digest.days} days',
      ),
      _StatTile(
        icon: Icons.celebration_outlined,
        label: l10n(context).prayersAnswered,
        value: '${digest.prayersAnswered}',
      ),
      _StatTile(
        icon: Icons.note_add_outlined,
        label: l10n(context).notesCreated,
        value: '${digest.notesCreated}',
        sub: '${digest.notesEdited} edited',
      ),
      _StatTile(
        icon: Icons.menu_book_outlined,
        label: l10n(context).chaptersOpened,
        value: '${digest.chaptersOpened}',
      ),
      _StatTile(
        icon: Icons.people_outline,
        label: l10n(context).peopleMentioned,
        value: '${digest.peopleMentioned}',
      ),
    ];
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.6,
      children: tiles,
    );
  }
}

class _StatTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String? sub;

  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
    this.sub,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Icon(icon, color: theme.colorScheme.primary),
            Text(
              value,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(label, style: theme.textTheme.bodySmall),
            if (sub != null)
              Text(
                sub!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TopList extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<String> entries;
  const _TopList({
    required this.title,
    required this.icon,
    required this.entries,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: theme.colorScheme.primary, size: 20),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...entries.map(
              (e) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    const Text('• '),
                    Expanded(
                      child: Text(
                        e,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.calendar_today_outlined,
                size: 48, color: theme.disabledColor),
            const SizedBox(height: 12),
            Text(l10n(context).noActivityThisWeek, style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              l10n(context).logAPrayerCaptureANoteOrOpenTheBibleToSeeYou,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

