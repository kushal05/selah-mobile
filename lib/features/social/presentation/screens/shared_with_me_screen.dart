import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/sync/models/entity_access_model.dart';
import '../../../../core/sync/providers/sync_providers.dart';

/// Inbox for incoming tier-2 user shares.
///
/// Shows pending shares (unaccepted) at the top with Accept/Decline actions,
/// then accepted shares below with a shortcut to open the note.
///
/// Deeplink: `/share/me` — opens this screen. Accepting a share transitions
/// the row from Pending → Accepted without leaving the inbox so the user
/// can accept multiple without the screen popping back.
class SharedWithMeScreen extends ConsumerWidget {
  const SharedWithMeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(pendingIncomingSharesProvider);
    final accepted = ref.watch(acceptedIncomingSharesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Shared with me')),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          _SectionHeader(label: 'Pending'),
          pending.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (err, _) => _ErrorTile(message: '$err'),
            data: (items) => items.isEmpty
                ? const _EmptyTile(
                    message: 'No pending invites.',
                    icon: Icons.inbox_outlined,
                  )
                : Column(
                    children: items
                        .map((s) => _PendingShareTile(share: s))
                        .toList(),
                  ),
          ),
          const SizedBox(height: 24),
          _SectionHeader(label: 'Active'),
          accepted.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (err, _) => _ErrorTile(message: '$err'),
            data: (items) => items.isEmpty
                ? const _EmptyTile(
                    message: 'Nothing has been shared with you yet.',
                    icon: Icons.folder_shared_outlined,
                  )
                : Column(
                    children: items
                        .map((s) => _AcceptedShareTile(share: s))
                        .toList(),
                  ),
          ),
        ],
      ),
    );
  }
}

class _PendingShareTile extends ConsumerStatefulWidget {
  final EntityAccessModel share;
  const _PendingShareTile({required this.share});

  @override
  ConsumerState<_PendingShareTile> createState() => _PendingShareTileState();
}

class _PendingShareTileState extends ConsumerState<_PendingShareTile> {
  bool _busy = false;

  Future<void> _accept() async {
    setState(() => _busy = true);
    try {
      final repo = ref.read(entityAccessRepositoryProvider);
      await repo.acceptAccess(widget.share.id);
      // Providers stream off Drift, so UI updates automatically.
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Share accepted')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to accept: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _decline() async {
    setState(() => _busy = true);
    try {
      final repo = ref.read(entityAccessRepositoryProvider);
      await repo.deleteAccess(widget.share.id);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to decline: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.share;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.insert_drive_file_outlined),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _entityLabel(s),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                _RolePill(role: s.role),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Invited ${_relative(s.createdAt)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _busy ? null : _decline,
                    child: const Text('Decline'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: _busy ? null : _accept,
                    child: _busy
                        ? const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Accept'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AcceptedShareTile extends StatelessWidget {
  final EntityAccessModel share;
  const _AcceptedShareTile({required this.share});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.folder_shared_outlined),
      title: Text(_entityLabel(share)),
      subtitle: Text(
        'Accepted ${share.acceptedAt == null ? 'recently' : _relative(share.acceptedAt!)}',
      ),
      trailing: _RolePill(role: share.role),
      onTap: () => _openEntity(context, share),
    );
  }
}

void _openEntity(BuildContext context, EntityAccessModel share) {
  if (share.entityType == 'note') {
    // Reuse the existing note route. If it doesn't already handle
    // not-yet-replicated content gracefully, the viewer shows a loading
    // state while the sync backfill lands.
    context.push('/notes/${share.entityId}');
  }
}

class _RolePill extends StatelessWidget {
  final AccessRole role;
  const _RolePill({required this.role});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = role.canEdit ? 'Edit' : 'View';
    final color = role.canEdit
        ? theme.colorScheme.primary
        : theme.colorScheme.outline;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(color: color),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge,
      ),
    );
  }
}

class _EmptyTile extends StatelessWidget {
  final String message;
  final IconData icon;
  const _EmptyTile({required this.message, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          Icon(icon, size: 40, color: Theme.of(context).disabledColor),
          const SizedBox(height: 8),
          Text(message, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}

class _ErrorTile extends StatelessWidget {
  final String message;
  const _ErrorTile({required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Text(
        message,
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      ),
    );
  }
}

String _entityLabel(EntityAccessModel s) {
  switch (s.entityType) {
    case 'note':
      return 'Shared note';
    default:
      return 'Shared ${s.entityType}';
  }
}

String _relative(int ms) {
  final diff = DateTime.now().millisecondsSinceEpoch - ms;
  if (diff < 60 * 1000) return 'just now';
  if (diff < 60 * 60 * 1000) return '${diff ~/ 60000}m ago';
  if (diff < 24 * 60 * 60 * 1000) return '${diff ~/ 3600000}h ago';
  return '${diff ~/ 86400000}d ago';
}
