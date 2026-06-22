import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/models/note_revision.dart';
import '../providers/database_provider.dart';
import '../widgets/revision_diff_view.dart';
import '../../../../shared/widgets/skeletons/skeletons.dart';

/// Screen showing the snapshot-based revision history of a note.
///
/// Users can preview a revision, compare it with the current version (diff),
/// or restore the note to a previous state.
class NoteVersionHistoryScreen extends ConsumerWidget {
  final String noteId;

  const NoteVersionHistoryScreen({super.key, required this.noteId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final revisionsAsync = ref.watch(noteRevisionsProvider(noteId));
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Version History'),
      ),
      body: revisionsAsync.when(
        loading: () => const ListTileSkeletonList(count: 5, hasLeading: false),
        error: (e, _) => Center(child: Text('Error loading history: $e')),
        data: (revisions) {
          if (revisions.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.history,
                      size: 48, color: cs.onSurface.withValues(alpha: 0.3)),
                  const SizedBox(height: 12),
                  Text(
                    'No revisions yet',
                    style: TextStyle(
                      color: cs.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Revisions are created each time you save.',
                    style: TextStyle(
                      fontSize: 12,
                      color: cs.onSurface.withValues(alpha: 0.4),
                    ),
                  ),
                ],
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 16),
            itemCount: revisions.length,
            separatorBuilder: (_, _) => const SizedBox(height: 0),
            itemBuilder: (context, index) {
              final revision = revisions[index];
              return _RevisionTile(
                revision: revision,
                noteId: noteId,
                isFirst: index == 0,
                isLast: index == revisions.length - 1,
                isCurrent: index == 0,
              );
            },
          );
        },
      ),
    );
  }
}

class _RevisionTile extends ConsumerWidget {
  final NoteRevisionSnapshot revision;
  final String noteId;
  final bool isFirst;
  final bool isLast;
  final bool isCurrent;

  const _RevisionTile({
    required this.revision,
    required this.noteId,
    this.isFirst = false,
    this.isLast = false,
    this.isCurrent = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final dateTime = revision.createdAt;

    return InkWell(
      onTap: () => _showRevisionActions(context, ref),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Timeline line + dot
              SizedBox(
                width: 32,
                child: Column(
                  children: [
                    if (!isFirst)
                      Expanded(
                        child: Container(
                          width: 2,
                          color: cs.outline.withValues(alpha: 0.2),
                        ),
                      ),
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: isCurrent
                            ? AppTheme.brandPurple
                            : cs.outline.withValues(alpha: 0.4),
                        shape: BoxShape.circle,
                      ),
                    ),
                    if (!isLast)
                      Expanded(
                        child: Container(
                          width: 2,
                          color: cs.outline.withValues(alpha: 0.2),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // Content
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (isCurrent)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 1),
                              margin: const EdgeInsets.only(right: 8),
                              decoration: BoxDecoration(
                                color: AppTheme.brandPurple
                                    .withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'Latest',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.brandPurple,
                                ),
                              ),
                            ),
                          Text(
                            '${revision.blockCount} blocks',
                            style: TextStyle(
                              fontSize: 12,
                              color: cs.onSurface.withValues(alpha: 0.5),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        revision.title,
                        style: theme.textTheme.bodyMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _formatTimestamp(dateTime),
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurface.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Chevron
              Center(
                child: Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: cs.onSurface.withValues(alpha: 0.3),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTimestamp(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);

    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';

    final month = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ][dt.month - 1];
    final time =
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    return '$month ${dt.day}, ${dt.year} at $time';
  }

  void _showRevisionActions(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    // Capture the scaffold messenger before any async gaps.
    final messenger = ScaffoldMessenger.of(context);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => DraggableScrollableSheet(
        initialChildSize: 0.55,
        minChildSize: 0.3,
        maxChildSize: 0.85,
        expand: false,
        builder: (sheetContext, scrollController) {
          final snapshot = revision.deserialize();

          // Guard against corrupt snapshot JSON.
          if (snapshot == null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'Unable to read this revision.',
                  style: TextStyle(color: cs.error),
                ),
              ),
            );
          }

          final blocks = snapshot.blocks;

          return Column(
            children: [
              // Handle
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 4),
                  width: 32,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    const Icon(Icons.history,
                        color: AppTheme.brandPurple, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Revision — ${_formatTimestamp(revision.createdAt)}',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Action buttons
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(sheetContext);
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => RevisionDiffView(
                                noteId: noteId,
                                revision: revision,
                              ),
                            ),
                          );
                        },
                        icon: const Icon(Icons.compare_arrows, size: 18),
                        label: const Text('Compare'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () =>
                            _confirmRestore(sheetContext, ref, messenger),
                        icon: const Icon(Icons.restore, size: 18),
                        label: const Text('Restore'),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.brandPurple,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Divider(height: 1, color: Colors.grey.shade200),
              // Preview content
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(
                      snapshot.note.title,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ...blocks.map((block) {
                      final text = block.plainText;
                      if (text.isEmpty &&
                          block.blockType.name == 'paragraph') {
                        return const SizedBox(height: 8);
                      }
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(
                          text,
                          style: _blockTextStyle(
                              theme, block.blockType.name),
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  TextStyle _blockTextStyle(ThemeData theme, String blockType) {
    return switch (blockType) {
      'heading1' => theme.textTheme.headlineSmall!
          .copyWith(fontWeight: FontWeight.bold),
      'heading2' =>
        theme.textTheme.titleLarge!.copyWith(fontWeight: FontWeight.bold),
      'heading3' => theme.textTheme.titleMedium!
          .copyWith(fontWeight: FontWeight.bold),
      'quote' => theme.textTheme.bodyLarge!.copyWith(
          fontStyle: FontStyle.italic,
          color: theme.colorScheme.onSurface.withValues(alpha: 0.7)),
      'code' => theme.textTheme.bodyMedium!
          .copyWith(fontFamily: 'monospace'),
      _ => theme.textTheme.bodyLarge!,
    };
  }

  Future<void> _confirmRestore(
    BuildContext context,
    WidgetRef ref,
    ScaffoldMessengerState messenger,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Restore Revision'),
        content: const Text(
          'This will replace the current note with this revision. '
          'A snapshot of the current version will be saved before restoring.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style:
                FilledButton.styleFrom(backgroundColor: AppTheme.brandPurple),
            child: const Text('Restore'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (!context.mounted) return;

    // Close the bottom sheet.
    Navigator.pop(context);

    try {
      final restoreService = ref.read(noteRestoreServiceProvider);
      await restoreService.restore(revision.id);

      messenger.showSnackBar(
        const SnackBar(
          content: Text('Note restored to previous version'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Failed to restore: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}
