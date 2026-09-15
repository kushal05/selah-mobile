import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/sync/providers/sync_providers.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/skeletons/skeletons.dart';
import '../../../../core/services/user_facing_error.dart';
import '../../../../core/theme/theme_colors.dart';
import '../../../../l10n/l10n.dart';
import '../../../../shared/utils/date_format.dart';

/// Global prayer updates feed screen.
///
/// Shows all prayer updates across all prayers, sorted by newest first.
class PrayerUpdatesFeedScreen extends ConsumerWidget {
  const PrayerUpdatesFeedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final updatesAsync = ref.watch(allPrayerUpdatesProvider);
    final prayersAsync = ref.watch(prayersStreamProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n(context).prayerUpdates),
        backgroundColor: Theme.of(context).colorScheme.surface,
        elevation: 0,
      ),
      body: updatesAsync.when(
        loading: () => const Column(children: [FeedItemSkeleton(), FeedItemSkeleton(), FeedItemSkeleton(), FeedItemSkeleton()]),
        error: (e, _) => Center(child: Text(UserFacingError.forLoad(e))),
        data: (updates) {
          if (updates.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.chat_bubble_outline,
                      size: 48, color: context.hintText),
                  const SizedBox(height: 12),
                  Text(l10n(context).noUpdatesYet,
                      style: TextStyle(
                          fontSize: 16, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 8),
                  Text(l10n(context).addUpdatesToYourPrayersToSeeThemHere,
                      style: TextStyle(
                          fontSize: 14, color: context.mutedText)),
                ],
              ),
            );
          }

          // Build prayer title lookup
          final prayers = prayersAsync.valueOrNull ?? [];
          final prayerMap = {for (final p in prayers) p.id: p.title};

          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: updates.length,
            separatorBuilder: (_, _) =>
                Divider(height: 1, indent: 16, color: context.hairline),
            itemBuilder: (context, index) {
              final update = updates[index];
              final prayerTitle =
                  prayerMap[update.prayerId] ?? 'Unknown Prayer';
              final date = DateTime.fromMillisecondsSinceEpoch(
                  update.createdAt);

              return ListTile(
                onTap: () => context.push('/prayers/${update.prayerId}'),
                title: Text(
                  update.content,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 16),
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    children: [
                      const Icon(Icons.favorite_border,
                          size: 14, color: AppTheme.brandPurple),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          prayerTitle,
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppTheme.brandPurple,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        _formatDate(context, date),
                        style: TextStyle(
                            fontSize: 12, color: context.mutedText),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  String _formatDate(BuildContext context, DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inMinutes < 60) return l10n(context).nMinutesAgo(diff.inMinutes);
    if (diff.inHours < 24) return l10n(context).nHoursAgo(diff.inHours);
    if (diff.inDays == 1) return l10n(context).yesterday;
    if (diff.inDays < 7) return l10n(context).nDaysAgo(diff.inDays);
    return formatShortDate(date);
  }
}
