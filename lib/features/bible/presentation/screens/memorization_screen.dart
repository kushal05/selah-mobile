import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../domain/models/memory_verse.dart';
import '../providers/memory_verse_providers.dart';

/// Home for scripture memorization: lists all cards, surfaces the due count,
/// links into the review session, and opens an add-card sheet.
class MemorizationScreen extends ConsumerWidget {
  const MemorizationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final versesAsync = ref.watch(memoryVersesStreamProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Memorization')),
      floatingActionButton: FloatingActionButton(
        heroTag: null,
        onPressed: () => _showAddSheet(context, ref),
        child: const Icon(Icons.add),
      ),
      body: versesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (verses) {
          final now = DateTime.now().millisecondsSinceEpoch;
          final dueCount = verses.where((v) => v.dueAt <= now).length;

          if (verses.isEmpty) {
            return _Empty(onAdd: () => _showAddSheet(context, ref));
          }

          return Column(
            children: [
              if (dueCount > 0)
                Container(
                  margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: ElevatedButton.icon(
                    onPressed: () =>
                        context.push('/bible/memorization/review'),
                    icon: const Icon(Icons.psychology_outlined),
                    label: Text(
                      'Review $dueCount due',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: Colors.white,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      backgroundColor: theme.colorScheme.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: verses.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (_, i) {
                    final v = verses[i];
                    return _VerseCard(
                      verse: v,
                      onDelete: () =>
                          ref.read(memoryVerseRepositoryProvider).remove(v.id),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showAddSheet(BuildContext context, WidgetRef ref) async {
    final reference = TextEditingController();
    final text = TextEditingController();
    final version = TextEditingController();
    final navigator = Navigator.of(context);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetCtx) => Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          bottom: MediaQuery.of(sheetCtx).viewInsets.bottom + 16,
          top: 8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'New memory verse',
              style: Theme.of(sheetCtx).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reference,
              decoration: const InputDecoration(
                labelText: 'Reference (e.g. John 3:16)',
                border: OutlineInputBorder(),
              ),
              autofocus: true,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: version,
              decoration: const InputDecoration(
                labelText: 'Translation (optional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: text,
              minLines: 3,
              maxLines: 6,
              decoration: const InputDecoration(
                labelText: 'Verse text',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () async {
                if (reference.text.trim().isEmpty ||
                    text.text.trim().isEmpty) {
                  return;
                }
                final verse = MemoryVerse.create(
                  id: const Uuid().v4(),
                  reference: reference.text.trim(),
                  text: text.text.trim(),
                  version: version.text.trim(),
                );
                await ref.read(memoryVerseRepositoryProvider).upsert(verse);
                ref.invalidate(dueMemoryVersesProvider);
                navigator.pop();
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}

class _VerseCard extends StatelessWidget {
  final MemoryVerse verse;
  final VoidCallback onDelete;
  const _VerseCard({required this.verse, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dueText = verse.isDue
        ? 'Due now'
        : 'Next: ${_formatDue(verse.dueAt)}';
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          verse.reference,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (verse.version.isNotEmpty)
                        Text(
                          verse.version,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.5),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    verse.text,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.schedule, size: 14,
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.5)),
                      const SizedBox(width: 4),
                      Text(
                        dueText,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.6),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Step ${verse.reviewCount}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Delete',
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }

  String _formatDue(int ms) {
    final now = DateTime.now();
    final due = DateTime.fromMillisecondsSinceEpoch(ms);
    final diff = due.difference(now);
    if (diff.inDays > 0) return 'in ${diff.inDays}d';
    if (diff.inHours > 0) return 'in ${diff.inHours}h';
    return 'soon';
  }
}

class _Empty extends StatelessWidget {
  final VoidCallback onAdd;
  const _Empty({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.psychology_outlined,
                size: 48, color: theme.disabledColor),
            const SizedBox(height: 12),
            Text('No memory verses yet',
                style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              'Add a verse and review it across spaced intervals (1, 3, 7, 14, 30, 60, 120, 240 days).',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Add your first verse'),
              onPressed: onAdd,
            ),
          ],
        ),
      ),
    );
  }
}
