import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/sync/models/tag_model.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/sync/providers/sync_providers.dart';
import '../../../../shared/widgets/skeletons/skeletons.dart';

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
        title: const Text('Tags'),
      ),
      body: tagsAsync.when(
        loading: () => const ListTileSkeletonList(count: 6, hasLeading: false),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (tags) {
          if (tags.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.label_outline,
                      size: 48, color: cs.onSurface.withValues(alpha: 0.3)),
                  const SizedBox(height: AppTheme.spacing12),
                  Text(
                    'No tags yet',
                    style: AppTheme.headingSmall.copyWith(
                      color: cs.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                  const SizedBox(height: AppTheme.spacing4),
                  Text(
                    'Tags added to notes and songs will appear here',
                    style: AppTheme.bodySmallStyle.copyWith(
                      color: cs.onSurface.withValues(alpha: 0.4),
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
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return ListTile(
      leading: Icon(Icons.label_outline,
          color: AppTheme.brandPurple, size: AppTheme.iconLG),
      title: Text(tag.name),
      subtitle: Text(
        '$usageCount ${usageCount == 1 ? 'use' : 'uses'}',
        style: AppTheme.caption.copyWith(
            color: cs.onSurface.withValues(alpha: 0.5)),
      ),
      trailing: PopupMenuButton<String>(
        icon: Icon(Icons.more_vert,
            color: cs.onSurface.withValues(alpha: 0.5)),
        onSelected: (action) =>
            _handleAction(context, ref, action),
        itemBuilder: (context) => [
          const PopupMenuItem(value: 'rename', child: Text('Rename')),
          const PopupMenuItem(value: 'merge', child: Text('Merge into...')),
          const PopupMenuItem(
            value: 'delete',
            child: Text('Delete', style: TextStyle(color: Colors.red)),
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
        title: const Text('Rename Tag'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Tag name',
            border: OutlineInputBorder(),
          ),
          textCapitalization: TextCapitalization.words,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
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
                    SnackBar(content: Text('$e')),
                  );
                }
              }
            },
            child: const Text('Rename'),
          ),
        ],
      ),
    );
  }

  void _showMergeSheet(BuildContext context, WidgetRef ref) {
    final targets = allTags.where((t) => t.id != tag.id).toList();
    if (targets.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No other tags to merge with')),
      );
      return;
    }

    showModalBottomSheet(
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
                          SnackBar(content: Text('$e')),
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
            title: const Text('Merge Tags?'),
            content: Text(
              'All items tagged "$source" will be re-tagged with "$target". '
              'The "$source" tag will be deleted. This cannot be undone.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Merge'),
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
        title: const Text('Delete Tag?'),
        content: Text(
          'The tag "${tag.name}" will be removed. '
          'Notes and songs will not be deleted, only untagged.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
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
                    SnackBar(content: Text('$e')),
                  );
                }
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
