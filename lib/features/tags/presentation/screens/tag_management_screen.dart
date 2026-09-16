import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/sync/models/tag_model.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/sync/providers/sync_providers.dart';
import '../../../../shared/widgets/skeletons/skeletons.dart';
import '../../../../core/services/user_facing_error.dart';
import '../../../../core/theme/theme_colors.dart';
import '../../../../l10n/l10n.dart';

/// Provider that fetches usage counts for all tags.
final tagUsageCountsProvider =
    FutureProvider<Map<String, int>>((ref) async {
  final tagRepo = ref.watch(tagRepositoryProvider);
  final userId = ref.watch(currentUserIdProvider);
  return tagRepo.getTagUsageCounts(userId);
});

/// Dedicated screen for managing tags: rename, merge, and delete.
class TagManagementScreen extends ConsumerWidget {
  const TagManagementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tagsAsync = ref.watch(tagsStreamProvider);
    final usageCountsAsync = ref.watch(tagUsageCountsProvider);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n(context).tags),
      ),
      body: tagsAsync.when(
        loading: () => const ListTileSkeletonList(count: 6, hasLeading: false),
        error: (e, _) => Center(child: Text(UserFacingError.forLoad(e))),
        data: (tags) {
          if (tags.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.label_outline,
                      size: 48, color: context.mutedText),
                  const SizedBox(height: AppTheme.spacing12),
                  Text(
                    l10n(context).noTagsYet,
                    style: AppTheme.headingSmall.copyWith(
                      color: context.mutedText,
                    ),
                  ),
                  const SizedBox(height: AppTheme.spacing4),
                  Text(
                    l10n(context).tagsAddedToNotesAndSongsWillAppearHere,
                    style: AppTheme.bodySmallStyle.copyWith(
                      color: context.mutedText,
                    ),
                  ),
                ],
              ),
            );
          }

          final usageCounts =
              usageCountsAsync.valueOrNull ?? <String, int>{};

          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: AppTheme.spacing8),
            itemCount: tags.length,
            separatorBuilder: (_, _) =>
                Divider(height: 1, indent: 56, color: cs.outline.withValues(alpha: 0.1)),
            itemBuilder: (context, index) {
              final tag = tags[index];
              final count = usageCounts[tag.id] ?? 0;
              return _TagTile(
                tag: tag,
                usageCount: count,
                allTags: tags,
              );
            },
          );
        },
      ),
    );
  }
}

class _TagTile extends ConsumerWidget {
  final TagModel tag;
  final int usageCount;
  final List<TagModel> allTags;

  const _TagTile({
    required this.tag,
    required this.usageCount,
    required this.allTags,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {

    return ListTile(
      leading: Icon(Icons.label_outline,
          color: AppTheme.brandPurple, size: AppTheme.iconLG),
      title: Text(tag.name),
      subtitle: Text(
        '$usageCount ${usageCount == 1 ? 'use' : 'uses'}',
        style: AppTheme.caption.copyWith(
            color: context.mutedText),
      ),
      trailing: PopupMenuButton<String>(
        icon: Icon(Icons.more_vert,
            color: context.mutedText),
        onSelected: (action) =>
            _handleAction(context, ref, action),
        itemBuilder: (context) => [
          PopupMenuItem(value: 'rename', child: Text(l10n(context).rename)),
          PopupMenuItem(value: 'merge', child: Text(l10n(context).mergeInto)),
          PopupMenuItem(
            value: 'delete',
            child: Text(l10n(context).actionDelete, style: TextStyle(color: context.dangerText)),
          ),
        ],
      ),
    );
  }

  void _handleAction(BuildContext context, WidgetRef ref, String action) {
    switch (action) {
      case 'rename':
        _showRenameDialog(context, ref);
      case 'merge':
        _showMergeSheet(context, ref);
      case 'delete':
        _showDeleteConfirmation(context, ref);
    }
  }

  void _showRenameDialog(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController(text: tag.name);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n(context).renameTag),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            labelText: l10n(context).tagName2,
            border: OutlineInputBorder(),
          ),
          textCapitalization: TextCapitalization.words,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n(context).actionCancel),
          ),
          FilledButton(
            onPressed: () async {
              final newName = controller.text.trim();
              if (newName.isEmpty || newName == tag.name) {
                Navigator.pop(ctx);
                return;
              }
              try {
                final tagRepo = ref.read(tagRepositoryProvider);
                await tagRepo.renameTag(id: tag.id, newName: newName);
                if (ctx.mounted) Navigator.pop(ctx);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Renamed to "$newName"')),
                  );
                  ref.invalidate(tagUsageCountsProvider);
                }
              } catch (e) {
                if (ctx.mounted) Navigator.pop(ctx);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(UserFacingError.message(e, action: 'update that tag'))),
                  );
                }
              }
            },
            child: Text(l10n(context).rename),
          ),
        ],
      ),
    );
  }

  void _showMergeSheet(BuildContext context, WidgetRef ref) {
    final targets = allTags.where((t) => t.id != tag.id).toList();
    if (targets.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n(context).noOtherTagsToMergeWith)),
      );
      return;
    }

    showModalBottomSheet(
      // Defaults to false: a scroll-controlled sheet otherwise draws its
      // top edge behind the notch or Dynamic Island.
      useSafeArea: true,
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.radius3XL)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AppTheme.spacing16, AppTheme.spacing16, AppTheme.spacing16, AppTheme.spacing8),
              child: Text(
                'Merge "${tag.name}" into...',
                style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
            Padding(
              padding: AppTheme.paddingH16,
              child: Text(
                'All items tagged "${tag.name}" will be re-tagged with the selected tag.',
                style: AppTheme.bodySmallStyle.copyWith(
                  color: Theme.of(ctx)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.5),
                ),
              ),
            ),
            const SizedBox(height: AppTheme.spacing8),
            ...targets.map(
              (target) => ListTile(
                leading: const Icon(Icons.label_outline,
                    color: AppTheme.brandPurple),
                title: Text(target.name),
                onTap: () async {
                  Navigator.pop(ctx);
                  final confirmed = await _confirmMerge(
                      context, tag.name, target.name);
                  if (confirmed && context.mounted) {
                    try {
                      final tagRepo = ref.read(tagRepositoryProvider);
                      await tagRepo.mergeTags(
                        sourceTagId: tag.id,
                        targetTagId: target.id,
                      );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                                'Merged "${tag.name}" into "${target.name}"'),
                          ),
                        );
                        ref.invalidate(tagUsageCountsProvider);
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(UserFacingError.message(e, action: 'update that tag'))),
                        );
                      }
                    }
                  }
                },
              ),
            ),
            const SizedBox(height: AppTheme.spacing8),
          ],
        ),
      ),
    );
  }

  Future<bool> _confirmMerge(
      BuildContext context, String source, String target) async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(l10n(context).mergeTags),
            content: Text(
              'All items tagged "$source" will be re-tagged with "$target". '
              'The "$source" tag will be deleted. This cannot be undone.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(l10n(context).actionCancel),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(l10n(context).merge),
              ),
            ],
          ),
        ) ??
        false;
  }

  void _showDeleteConfirmation(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n(context).deleteTag),
        content: Text(
          'The tag "${tag.name}" will be removed. '
          'Notes and songs will not be deleted, only untagged.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n(context).actionCancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                final tagRepo = ref.read(tagRepositoryProvider);
                await tagRepo.deleteTag(tag.id);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Tag "${tag.name}" deleted')),
                  );
                  ref.invalidate(tagUsageCountsProvider);
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(UserFacingError.message(e, action: 'update that tag'))),
                  );
                }
              }
            },
            child: Text(l10n(context).actionDelete),
          ),
        ],
      ),
    );
  }
}
