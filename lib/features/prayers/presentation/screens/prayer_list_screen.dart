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
import '../../../../shared/widgets/undo_snackbar.dart';
import '../../../../core/services/user_facing_error.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../../../shared/widgets/row_actions.dart';
import '../../../../core/theme/theme_colors.dart';
import '../../../../l10n/l10n.dart';
import '../widgets/quick_prayer_sheet.dart';
import '../../../../shared/widgets/swipe_action.dart';

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
              foregroundColor: AppTheme.onAccent(AppTheme.brandBlue),
              onPressed: () => showQuickPrayerSheet(context),
              child: const Icon(Icons.add),
            ),
      body: prayersAsync.when(
        loading: () => const ListTileSkeletonList(count: 8, hasLeading: false),
        error: (error, _) => Center(child: Text(UserFacingError.forLoad(error))),
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
      return EmptyTrashState(itemsLabel: l10n(context).trashLabelPrayers);
    }
    // A filtered view that is empty is a different situation from having no
    // prayers at all, and needs different words — nothing is wrong here.
    if (widget.status != null) {
      final status = widget.status!.displayName.toLowerCase();
      return EmptyState(
        icon: Icons.favorite_border_rounded,
        title: l10n(context).noStatusPrayers(status),
        message: l10n(context).prayersYouMarkAsStatusWillShowUpHere(status),
        accent: AppTheme.brandBlue,
      );
    }
    return EmptyState(
      icon: Icons.favorite_border_rounded,
      title: l10n(context).noPrayersYet,
      message: l10n(context).writeDownWhatYouWantToPrayForYouCanMarkPraye,
      actionLabel: l10n(context).addYourFirstPrayer,
      onAction: () => showQuickPrayerSheet(context),
      accent: AppTheme.brandBlue,
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
          buildSwipeAction(
            icon: Icons.delete,
            label: l10n(context).moveToTrash,
            accent: AppTheme.error,
            onPressed: (_) async {
              final confirmed = await _showDeleteConfirmation(context);
              if (confirmed && context.mounted) {
                final repo = ref.read(prayerRepositoryProvider);
                try {
                  await repo.trashPrayer(prayer.id);
                } catch (e) {
                  // Otherwise the delete fails with no feedback at all.
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(UserFacingError.message(e,
                          action: 'move this prayer to Trash')),
                      backgroundColor: AppTheme.errorSurface,
                    ),
                  );
                  return;
                }
                if (!context.mounted) return;
                showUndoSnackBar(
                  context,
                  itemLabel: l10n(context).prayer,
                  onUndo: () => repo.restorePrayer(prayer.id),
                );
              }
            },
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
        actions: [
          RowAction(
            icon: Icons.delete_outline_rounded,
            label: l10n(context).moveToTrash,
            isDestructive: true,
            onSelected: () async {
              final confirmed = await _showDeleteConfirmation(context);
              if (!confirmed || !context.mounted) return;
              final repo = ref.read(prayerRepositoryProvider);
              try {
                await repo.trashPrayer(prayer.id);
              } catch (e) {
                // Otherwise the delete fails with no feedback at all.
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(UserFacingError.message(e,
                        action: 'move this prayer to Trash')),
                    backgroundColor: AppTheme.errorSurface,
                  ),
                );
                return;
              }
              if (!context.mounted) return;
              showUndoSnackBar(
                context,
                itemLabel: 'Prayer',
                onUndo: () => repo.restorePrayer(prayer.id),
              );
            },
          ),
        ],
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
            title: Text(l10n(context).moveToTrash),
            content:
                Text(l10n(context).areYouSureYouWantToMoveThisPrayerToTrash),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(l10n(context).actionCancel),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: Text(l10n(context).moveToTrash),
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
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        prayer.frequency.displayName,
        style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.restore),
            tooltip: l10n(context).restore,
            onPressed: () async {
              try {
                await ref.read(prayerRepositoryProvider).restorePrayer(prayer.id);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(l10n(context).prayerRestored),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(UserFacingError.message(e, action: 'restore')),
                      behavior: SnackBarBehavior.floating,
                      backgroundColor: AppTheme.errorSurface,
                    ),
                  );
                }
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_forever),
            tooltip: l10n(context).deletePermanently,
            color: context.dangerText,
            onPressed: () async {
              final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: Text(l10n(context).deletePermanently),
                      content: Text(
                          l10n(context).thisPrayerWillBePermanentlyDeletedThisCannot),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          child: Text(l10n(context).actionCancel),
                        ),
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(true),
                          style:
                              TextButton.styleFrom(foregroundColor: Colors.red),
                          child: Text(l10n(context).actionDelete),
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
                      SnackBar(
                        content: Text(l10n(context).prayerPermanentlyDeleted),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(UserFacingError.message(e, action: 'delete')),
                        behavior: SnackBarBehavior.floating,
                        backgroundColor: AppTheme.errorSurface,
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
