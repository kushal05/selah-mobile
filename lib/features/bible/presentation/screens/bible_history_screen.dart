import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/sync/models/bible_reference_history_model.dart';
import '../../../../core/sync/providers/sync_providers.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/navigation/routes.dart';
import '../providers/bible_providers.dart';

/// Groups history entries into Today / Yesterday / Older date buckets.
enum _DateGroup {
  today,
  yesterday,
  older;

  String get label {
    switch (this) {
      case _DateGroup.today:
        return 'Today';
      case _DateGroup.yesterday:
        return 'Yesterday';
      case _DateGroup.older:
        return 'Older';
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
        title: Text('Reading History', style: AppTheme.headingMedium),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Clear all history',
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
              Text('Failed to load history',
                  style: TextStyle(color: theme.colorScheme.error)),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () =>
                    ref.invalidate(bibleReferenceHistoryStreamProvider),
                child: const Text('Retry'),
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
                    'No reading history yet',
                    style: AppTheme.bodyBase
                        .copyWith(color: theme.colorScheme.outline),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Open a Bible chapter to start tracking',
                    style: AppTheme.bodySmallStyle
                        .copyWith(color: theme.colorScheme.outline),
                  ),
                ],
              ),
            );
          }

          final grouped = _groupByDate(entries);
          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: AppTheme.spacing8),
            itemCount: grouped.length,
            itemBuilder: (context, index) {
              final group = grouped[index];
              return _DateGroupSection(
                group: group,
                onTap: (entry) => _navigateToChapter(context, ref, entry),
                onDelete: (entry) => _deleteEntry(ref, entry.id),
              );
            },
          );
        },
      ),
    );
  }

  /// Group entries into Today / Yesterday / Older buckets.
  List<_GroupedEntries> _groupByDate(
      List<BibleReferenceHistoryModel> entries) {
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
          label: _DateGroup.today.label, entries: today));
    }
    if (yesterday.isNotEmpty) {
      groups.add(_GroupedEntries(
          label: _DateGroup.yesterday.label, entries: yesterday));
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
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
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

  void _deleteEntry(WidgetRef ref, String id) {
    ref.read(bibleReferenceHistoryRepositoryProvider).deleteEntry(id);
  }

  void _confirmClearAll(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear Reading History'),
        content: const Text(
            'This will delete all your reading history. This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              final userId = ref.read(currentUserIdProvider);
              ref
                  .read(bibleReferenceHistoryRepositoryProvider)
                  .clearHistory(userId);
            },
            child: Text('Clear All',
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
        tooltip: 'Remove',
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
