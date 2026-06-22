import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/domain/enums/prayer_enums.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/sync/models/person_model.dart';
import '../../../../core/sync/models/prayer_model.dart';
import '../../../../core/sync/providers/sync_providers.dart';
import '../../../../shared/widgets/cards/prayer_card.dart';
import '../../../../shared/widgets/skeletons/skeletons.dart';
import '../../domain/models/prayer_metadata_codec.dart';

/// Screen that shows prayers filtered by status (Active, Answered, Archived)
/// or all prayers when no status filter is provided.
class PrayerListScreen extends ConsumerStatefulWidget {
  /// Null means show all prayers.
  final PrayerStatus? status;

  const PrayerListScreen({super.key, this.status});

  @override
  ConsumerState<PrayerListScreen> createState() => _PrayerListScreenState();
}

class _PrayerListScreenState extends ConsumerState<PrayerListScreen> {
  bool _showingTrash = false;

  String get _title {
    if (_showingTrash) return 'Trash';
    if (widget.status == null) return 'All Prayers';
    return '${widget.status!.displayName} Prayers';
  }

  @override
  Widget build(BuildContext context) {
    final prayersAsync = _showingTrash
        ? ref.watch(trashedPrayersStreamProvider)
        : widget.status != null
            ? ref.watch(prayersByStatusProvider(widget.status!))
            : ref.watch(prayersStreamProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(_title),
        actions: [
          IconButton(
            icon: Icon(_showingTrash ? Icons.list : Icons.delete_outline),
            tooltip: _showingTrash ? 'Show prayers' : 'Show trash',
            onPressed: () {
              setState(() {
                _showingTrash = !_showingTrash;
              });
            },
          ),
        ],
      ),
      floatingActionButton: _showingTrash
          ? null
          : FloatingActionButton(
              heroTag: null,
              backgroundColor: AppTheme.brandBlue,
              foregroundColor: Colors.white,
              onPressed: () => context.push('/prayers/new'),
              child: const Icon(Icons.add),
            ),
      body: prayersAsync.when(
        loading: () => const ListTileSkeletonList(count: 8, hasLeading: false),
        error: (error, _) => Center(child: Text('Error: $error')),
        data: (prayers) {
          if (prayers.isEmpty) {
            return _buildEmptyState(context);
          }

          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: prayers.length,
            itemBuilder: (context, index) {
              final prayer = prayers[index];
              if (_showingTrash) {
                return _TrashedPrayerListTile(prayer: prayer);
              }
              return _PrayerListTile(
                prayer: prayer,
                // When the list is already scoped to one status, the per-card
                // status chip is redundant — the badge tint conveys it.
                showStatusBadge: widget.status == null,
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    if (_showingTrash) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.delete_outline, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text(
              'Trash is empty',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
      );
    }

    final message = widget.status != null
        ? 'No ${widget.status!.displayName.toLowerCase()} prayers'
        : 'No prayers yet';

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.favorite_border, size: 48, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          Text(
            message,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Tap + to add a prayer request',
            style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }
}

class _PrayerListTile extends ConsumerWidget {
  final PrayerModel prayer;
  final bool showStatusBadge;

  const _PrayerListTile({required this.prayer, this.showStatusBadge = true});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusColor = _colorForStatus(prayer.status);

    final linkedIds = decodePrayerMetadata(prayer.category).linkedPeopleIds;
    final description =
        prayer.content.split('\n<!-- updates -->').first.trim();

    final peopleAsync = ref.watch(peopleStreamProvider);
    final isLoadingPeople = peopleAsync.isLoading;
    final peopleById = {
      for (final p in peopleAsync.valueOrNull ?? const <PersonModel>[]) p.id: p
    };
    final linkedNames = linkedIds
        .map((id) => peopleById[id]?.name ?? (isLoadingPeople ? '…' : '?'))
        .toList();

    return Slidable(
      key: Key(prayer.id),
      endActionPane: ActionPane(
        motion: const DrawerMotion(),
        extentRatio: 0.2,
        children: [
          SlidableAction(
            onPressed: (_) async {
              final confirmed = await _showDeleteConfirmation(context);
              if (confirmed && context.mounted) {
                ref.read(prayerRepositoryProvider).trashPrayer(prayer.id);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Moved to trash'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
            icon: Icons.delete,
            borderRadius: BorderRadius.circular(12),
          ),
        ],
      ),
      child: PrayerCard(
        title: prayer.title,
        frequencyLabel: prayer.frequency.displayName,
        statusLabel: prayer.status.displayName,
        statusColor: statusColor,
        description: description,
        linkedPeopleNames: linkedNames,
        showStatusBadge: showStatusBadge,
        onTap: () => context.push('/prayers/${prayer.id}'),
      ),
    );
  }

  Color _colorForStatus(PrayerStatus status) {
    switch (status) {
      case PrayerStatus.active:
        return AppTheme.brandBlue;
      case PrayerStatus.answered:
        return AppTheme.teal;
      case PrayerStatus.archived:
        return AppTheme.mutedGrey;
    }
  }

  Future<bool> _showDeleteConfirmation(BuildContext context) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Move to Trash'),
            content:
                const Text('Are you sure you want to move this prayer to trash?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('Move to Trash'),
              ),
            ],
          ),
        ) ??
        false;
  }
}

class _TrashedPrayerListTile extends ConsumerWidget {
  final PrayerModel prayer;

  const _TrashedPrayerListTile({required this.prayer});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      title: Text(
        prayer.title,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        prayer.frequency.displayName,
        style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.restore),
            tooltip: 'Restore',
            onPressed: () async {
              try {
                await ref.read(prayerRepositoryProvider).restorePrayer(prayer.id);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Prayer restored'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Failed to restore: $e'),
                      behavior: SnackBarBehavior.floating,
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_forever),
            tooltip: 'Delete permanently',
            color: Colors.red,
            onPressed: () async {
              final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Delete Permanently'),
                      content: const Text(
                          'This prayer will be permanently deleted. This cannot be undone.'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          child: const Text('Cancel'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(true),
                          style:
                              TextButton.styleFrom(foregroundColor: Colors.red),
                          child: const Text('Delete'),
                        ),
                      ],
                    ),
                  ) ??
                  false;
              if (confirmed && context.mounted) {
                try {
                  await ref
                      .read(prayerRepositoryProvider)
                      .deletePrayer(prayer.id);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Prayer permanently deleted'),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Failed to delete: $e'),
                        behavior: SnackBarBehavior.floating,
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              }
            },
          ),
        ],
      ),
    );
  }
}
