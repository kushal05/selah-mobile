import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/sync/models/bible_reference_history_model.dart';
import '../../../../core/sync/providers/sync_providers.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/navigation/routes.dart';
import '../providers/bible_providers.dart';
import '../../../../l10n/l10n.dart';
import '../../../../shared/utils/date_format.dart';

/// Groups history entries into Today / Yesterday / Older date buckets.
enum _DateGroup {
  today,
  yesterday,
  older;

  /// Takes a context because these are user-facing strings; an enum has no
  /// widget tree of its own to look them up in.
  String label(BuildContext context) {
    switch (this) {
      case _DateGroup.today:
        return l10n(context).today;
      case _DateGroup.yesterday:
        return l10n(context).yesterday;
      case _DateGroup.older:
        return l10n(context).older;
    }
  }
}

/// Screen displaying the user's Bible reading history, grouped by date.
class BibleHistoryScreen extends ConsumerWidget {
  const BibleHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(bibleReferenceHistoryStreamProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: theme.scaffoldBackgroundColor,
        elevation: 0,
        title: Text(l10n(context).readingHistory, style: AppTheme.headingMedium),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: l10n(context).clearAllHistory,
            onPressed: () => _confirmClearAll(context, ref),
          ),
        ],
      ),
      body: historyAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l10n(context).failedToLoadHistory,
                  style: TextStyle(color: theme.colorScheme.error)),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () =>
                    ref.invalidate(bibleReferenceHistoryStreamProvider),
                child: Text(l10n(context).retry),
              ),
            ],
          ),
        ),
        data: (entries) {
          if (entries.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.menu_book_outlined,
                      size: 64, color: theme.colorScheme.outline),
                  const SizedBox(height: 16),
                  Text(
                    l10n(context).noReadingHistoryYet,
                    style: AppTheme.bodyBase
                        .copyWith(color: theme.colorScheme.outline),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n(context).openABibleChapterToStartTracking,
                    style: AppTheme.bodySmallStyle
                        .copyWith(color: theme.colorScheme.outline),
                  ),
                ],
              ),
            );
          }

          final grouped = _groupByDate(context, entries);
          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: AppTheme.spacing8),
            itemCount: grouped.length,
            itemBuilder: (context, index) {
              final group = grouped[index];
              return _DateGroupSection(
                group: group,
                onTap: (entry) => _navigateToChapter(context, ref, entry),
                onDelete: (entry) =>
                    _deleteEntry(context, ref, entry.id),
              );
            },
          );
        },
      ),
    );
  }

  /// Group entries into Today / Yesterday / Older buckets.
  List<_GroupedEntries> _groupByDate(
      BuildContext context, List<BibleReferenceHistoryModel> entries) {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final yesterdayStart = todayStart.subtract(const Duration(days: 1));

    final today = <BibleReferenceHistoryModel>[];
    final yesterday = <BibleReferenceHistoryModel>[];
    final olderMap = <String, List<BibleReferenceHistoryModel>>{};

    for (final entry in entries) {
      final date = DateTime.fromMillisecondsSinceEpoch(entry.openedAt);
      if (date.isAfter(todayStart) ||
          date.isAtSameMomentAs(todayStart)) {
        today.add(entry);
      } else if (date.isAfter(yesterdayStart) ||
          date.isAtSameMomentAs(yesterdayStart)) {
        yesterday.add(entry);
      } else {
        final dateKey =
            '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
        olderMap.putIfAbsent(dateKey, () => []).add(entry);
      }
    }

    final groups = <_GroupedEntries>[];
    if (today.isNotEmpty) {
      groups.add(_GroupedEntries(
          label: _DateGroup.today.label(context), entries: today));
    }
    if (yesterday.isNotEmpty) {
      groups.add(_GroupedEntries(
          label: _DateGroup.yesterday.label(context), entries: yesterday));
    }
    // Sort older date keys descending
    final sortedDates = olderMap.keys.toList()..sort((a, b) => b.compareTo(a));
    for (final dateKey in sortedDates) {
      groups.add(_GroupedEntries(
          label: _formatDateLabel(dateKey),
          entries: olderMap[dateKey]!));
    }

    return groups;
  }

  String _formatDateLabel(String dateKey) {
    final parts = dateKey.split('-');
    final date = DateTime(
        int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
    return formatMediumDate(date);
  }

  void _navigateToChapter(
      BuildContext context, WidgetRef ref, BibleReferenceHistoryModel entry) {
    final repo = ref.read(bibleRepositoryProvider);
    final book = repo.getBookByName(entry.book);
    final bookId = book?.id ?? 1; // fallback to Genesis
    context.push(
      '${Routes.bible}/chapter'
      '?bookId=$bookId'
      '&chapter=${entry.chapter}'
      '&translation=${entry.translation}'
      '${entry.verseStart != null ? '&verse=${entry.verseStart}' : ''}',
    );
  }

  // Awaited, not fired and forgotten. An unawaited future that throws becomes
  // an unhandled async error, and the user's only clue was the row staying
  // where it was.
  Future<void> _deleteEntry(
      BuildContext context, WidgetRef ref, String id) async {
    final messenger = ScaffoldMessenger.of(context);
    final failed = l10n(context).couldNotRemoveHistoryEntry;
    try {
      await ref.read(bibleReferenceHistoryRepositoryProvider).deleteEntry(id);
    } catch (_) {
      messenger.showSnackBar(SnackBar(
        content: Text(failed),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  void _confirmClearAll(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n(context).clearReadingHistory),
        content: Text(
            l10n(context).thisWillDeleteAllYourReadingHistoryThisActio),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n(context).actionCancel),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              final userId = ref.read(currentUserIdProvider);
              ref
                  .read(bibleReferenceHistoryRepositoryProvider)
                  .clearHistory(userId);
            },
            child: Text(l10n(context).clearAll,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        ],
      ),
    );
  }
}

/// Internal grouping data class.
class _GroupedEntries {
  final String label;
  final List<BibleReferenceHistoryModel> entries;

  const _GroupedEntries({required this.label, required this.entries});
}

/// Section widget for a date group (Today, Yesterday, or a specific date).
class _DateGroupSection extends StatelessWidget {
  final _GroupedEntries group;
  final ValueChanged<BibleReferenceHistoryModel> onTap;
  final ValueChanged<BibleReferenceHistoryModel> onDelete;

  const _DateGroupSection({
    required this.group,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppTheme.spacing16, vertical: AppTheme.spacing8),
          child: Text(
            group.label,
            style: AppTheme.headingSmall.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        ...group.entries.map((entry) => _HistoryListTile(
              entry: entry,
              onTap: () => onTap(entry),
              onDelete: () => onDelete(entry),
            )),
        const SizedBox(height: AppTheme.spacing4),
      ],
    );
  }
}

/// Individual history entry tile.
class _HistoryListTile extends StatelessWidget {
  final BibleReferenceHistoryModel entry;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _HistoryListTile({
    required this.entry,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final time = DateTime.fromMillisecondsSinceEpoch(entry.openedAt);
    final timeStr = _formatTime(time);

    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: AppTheme.bibleGreen.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppTheme.radiusSM),
        ),
        child: const Icon(Icons.menu_book, color: AppTheme.bibleGreen, size: 20),
      ),
      title: Text(
        entry.formattedReference,
        style: AppTheme.bodyBase.copyWith(fontWeight: FontWeight.w500),
      ),
      subtitle: Text(
        '${entry.translation} · $timeStr',
        style: AppTheme.bodySmallStyle.copyWith(color: theme.colorScheme.outline),
      ),
      trailing: IconButton(
        icon: Icon(Icons.close, size: 18, color: theme.colorScheme.outline),
        onPressed: onDelete,
        tooltip: l10n(context).remove,
      ),
      onTap: onTap,
    );
  }

  String _formatTime(DateTime time) {
    final hour = time.hour;
    final minute = time.minute.toString().padLeft(2, '0');
    final period = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    return '$displayHour:$minute $period';
  }
}
