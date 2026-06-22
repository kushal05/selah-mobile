import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/sync/services/public_share_api_service.dart';
import '../providers/note_attribution_providers.dart';

/// Owner-facing activity feed for a note: who touched the note (or any of
/// its blocks) and when. Fetched on-demand from the server's
/// `/v1/notes/:id/activity` endpoint — this is not local-first data since
/// operations on fanned-out copies live on the server, not the owner's
/// device.
class NoteActivityScreen extends ConsumerWidget {
  final String noteId;
  const NoteActivityScreen({super.key, required this.noteId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activityAsync = ref.watch(noteActivityProvider(noteId));

    Future<void> refresh() async {
      ref.invalidate(noteActivityProvider(noteId));
      await ref.read(noteActivityProvider(noteId).future);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Activity'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: refresh,
          ),
        ],
      ),
      body: activityAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _ErrorState(error: error, onRetry: refresh),
        data: (items) {
          if (items.isEmpty) {
            return const _EmptyState();
          }
          return RefreshIndicator(
            onRefresh: refresh,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: items.length,
              separatorBuilder: (_, _) => const Divider(height: 0),
              itemBuilder: (_, i) => _ActivityTile(entry: items[i]),
            ),
          );
        },
      ),
    );
  }
}

class _ActivityTile extends StatelessWidget {
  final NoteActivityEntry entry;
  const _ActivityTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    final name = entry.displayName.isNotEmpty
        ? entry.displayName
        : (entry.username.isNotEmpty ? '@${entry.username}' : 'Someone');

    return ListTile(
      leading: CircleAvatar(
        child: Text(_initials(name)),
      ),
      title: Text(name),
      subtitle: Text(_describeAction(entry)),
      trailing: Text(
        _relative(entry.serverTimestamp),
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final Object error;
  final Future<void> Function() onRetry;
  const _ErrorState({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.history_toggle_off,
                size: 48, color: theme.colorScheme.error),
            const SizedBox(height: 12),
            Text('Couldn\'t load activity',
                style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              '$error',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              onPressed: onRetry,
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
            Icon(Icons.history_outlined,
                size: 48, color: theme.disabledColor),
            const SizedBox(height: 12),
            Text('No activity yet', style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              'Edits and views will appear here.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

String _describeAction(NoteActivityEntry e) {
  final target = e.entityType == 'note_block' ? 'a block' : 'the note';
  switch (e.operation) {
    case 'INSERT':
      return e.entityType == 'note_block' ? 'Added $target' : 'Created $target';
    case 'UPDATE':
      return 'Edited $target';
    case 'DELETE':
      return 'Deleted $target';
    default:
      return '${e.operation} on $target';
  }
}

String _initials(String name) {
  final clean = name.replaceFirst('@', '').trim();
  if (clean.isEmpty) return '?';
  final parts = clean.split(RegExp(r'\s+'));
  if (parts.length == 1) return parts[0][0].toUpperCase();
  return (parts[0][0] + parts.last[0]).toUpperCase();
}

String _relative(int ms) {
  final diff = DateTime.now().millisecondsSinceEpoch - ms;
  if (diff < 60 * 1000) return 'just now';
  if (diff < 60 * 60 * 1000) return '${diff ~/ 60000}m';
  if (diff < 24 * 60 * 60 * 1000) return '${diff ~/ 3600000}h';
  return '${diff ~/ 86400000}d';
}
