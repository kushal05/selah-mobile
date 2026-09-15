import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/sync/models/prayer_model.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/sync/models/promise_condition_model.dart';
import '../../../../core/sync/models/promise_model.dart';
import '../../../../core/sync/providers/sync_providers.dart';
import '../../../../shared/widgets/tag_row.dart';
import '../../../../shared/widgets/dialogs/link_picker_dialog.dart';
import '../../../../shared/widgets/skeletons/skeletons.dart';
import '../../../prayers/presentation/screens/prayer_detail_screen.dart';
import '../../../../shared/widgets/undo_snackbar.dart';
import '../../../../core/services/user_facing_error.dart';
import '../../../../core/theme/theme_colors.dart';
import '../../../../l10n/l10n.dart';

/// Promise detail screen showing verse, conditions, and notes
class PromiseDetailScreen extends ConsumerStatefulWidget {
  final String promiseId;

  const PromiseDetailScreen({super.key, required this.promiseId});

  @override
  ConsumerState<PromiseDetailScreen> createState() =>
      _PromiseDetailScreenState();
}

class _PromiseDetailScreenState extends ConsumerState<PromiseDetailScreen> {
  Future<void> _deletePromise() async {
    try {
      final repository = ref.read(promiseRepositoryProvider);
      await repository.trashPromise(widget.promiseId);
      if (mounted) {
        showUndoSnackBar(
          context,
          itemLabel: 'Promise',
          onUndo: () => repository.restorePromise(widget.promiseId),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(UserFacingError.forLoad(e))),
        );
      }
    }
  }

  Future<void> _toggleFavorite() async {
    try {
      final repository = ref.read(promiseRepositoryProvider);
      await repository.toggleFavorite(widget.promiseId);
      if (mounted) {
        ref.invalidate(promiseByIdProvider(widget.promiseId));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(UserFacingError.forLoad(e))),
        );
      }
    }
  }

  Future<void> _showLinkPrayerDialog() async {
    final userId = ref.read(currentUserIdProvider);
    final prayerRepo = ref.read(prayerRepositoryProvider);
    final allPrayers = await prayerRepo.getAllPrayers(userId);
    final linkedIds =
        ref.read(linkedPrayerIdsProvider(widget.promiseId)).valueOrNull ??
            [];

    if (!mounted) return;

    final selected = await LinkPicker.show<PrayerModel>(
      context,
      title: l10n(context).linkPrayers,
      items: allPrayers,
      alreadyLinkedIds: linkedIds.toSet(),
      getId: (p) => p.id,
      getLabel: (p) => p.title,
      getSubtitle: (p) => p.content.length > 120
          ? '${p.content.substring(0, 120)}…'
          : p.content,
      icon: Icons.favorite_outline_rounded,
    );

    if (selected != null && selected.isNotEmpty) {
      try {
        final linkRepo = ref.read(promisePrayerLinkRepositoryProvider);
        for (final prayerId in selected) {
          await linkRepo.linkPromiseToPrayer(
            promiseId: widget.promiseId,
            prayerId: prayerId,
            userId: userId,
          );
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  'Linked ${selected.length} prayer${selected.length > 1 ? 's' : ''}'),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(UserFacingError.message(e, action: 'link that'))),
          );
        }
      }
    }
  }

  Future<void> _unlinkPrayer(String prayerId) async {
    try {
      final linkRepo = ref.read(promisePrayerLinkRepositoryProvider);
      await linkRepo.unlinkPromiseFromPrayer(widget.promiseId, prayerId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n(context).prayerUnlinked)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(UserFacingError.message(e, action: 'unlink that'))),
        );
      }
    }
  }

  Widget _buildTagsFromProviders() {
    final tagIdsAsync =
        ref.watch(tagsForPromiseStreamProvider(widget.promiseId));
    final allTagsAsync = ref.watch(tagsStreamProvider);

    return tagIdsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (tagIds) {
        if (tagIds.isEmpty) return const SizedBox.shrink();
        return allTagsAsync.when(
          loading: () => const SizedBox.shrink(),
          error: (_, _) => const SizedBox.shrink(),
          data: (allTags) {
            final tagMap = {for (final t in allTags) t.id: t.name};
            final tagNames = tagIds
                .map((id) => tagMap[id])
                .where((name) => name != null)
                .cast<String>()
                .toList();
            if (tagNames.isEmpty) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(top: AppTheme.spacing8),
              child: TagRow(tags: tagNames),
            );
          },
        );
      },
    );
  }

  List<Widget> _buildNotesSection(BuildContext context, String notes) {
    if (notes.isEmpty) return [];
    return [
      const SizedBox(height: AppTheme.spacing24),
      Text(l10n(context).navNotes, style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: AppTheme.spacing8),
      Text(notes, style: Theme.of(context).textTheme.bodyLarge),
    ];
  }

  Widget _buildConditionsFromProviders() {
    final conditionsAsync =
        ref.watch(promiseConditionsByPromiseProvider(widget.promiseId));

    return conditionsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (conditions) {
        if (conditions.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: AppTheme.spacing24),
            Text(l10n(context).conditions,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppTheme.spacing8),
            ...conditions.map((c) => _buildConditionCard(context, c)),
          ],
        );
      },
    );
  }

  Widget _buildConditionCard(
      BuildContext context, PromiseConditionModel condition) {
    final status = condition.status.toDbValue();
    final isMet = status == 'MET';
    final color = isMet
        ? Colors.green
        : status == 'ACTIVE'
            ? Theme.of(context).colorScheme.primary
            : AppTheme.promiseInactive;

    return Container(
      margin: const EdgeInsets.only(bottom: AppTheme.spacing8),
      padding: AppTheme.paddingAllMD,
      decoration: BoxDecoration(
        color: context.cardSurface,
        borderRadius: AppTheme.borderRadiusXL,
        border: Border.all(color: context.subtleFill),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isMet ? Icons.check_circle : Icons.radio_button_unchecked,
                color: color,
                size: AppTheme.iconBase,
              ),
              const SizedBox(width: AppTheme.spacing8),
              Expanded(
                child: Text(condition.description,
                    style: const TextStyle(fontSize: 16)),
              ),
              Container(
                padding: AppTheme.chipPadding,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: AppTheme.alphaLightMed),
                  borderRadius: AppTheme.borderRadiusMD,
                ),
                child: Text(
                  status,
                  style: TextStyle(
                    fontSize: AppTheme.iconXS,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          if (condition.notes.isNotEmpty) ...[
            const SizedBox(height: AppTheme.spacing6),
            Text(
              condition.notes,
              style: TextStyle(fontSize: 14, color: context.mutedText),
            ),
          ],
        ],
      ),
    );
  }

  void _showDeleteConfirmation() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n(context).moveToTrash2),
        content: Text(l10n(context).areYouSureYouWantToMoveThisPromiseToTrash),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n(context).actionCancel),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deletePromise();
            },
            child: Text(l10n(context).moveToTrash, style: TextStyle(color: context.dangerText)),
          ),
        ],
      ),
    );
  }

  Widget _buildLinkedPrayersSection() {
    final linkedAsync = ref.watch(linkedPrayerIdsProvider(widget.promiseId));

    return linkedAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (prayerIds) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: AppTheme.spacing24),
            Row(
              children: [
                Icon(Icons.link, size: AppTheme.iconBase, color: context.mutedText),
                const SizedBox(width: AppTheme.spacing8),
                Text(l10n(context).linkedPrayers,
                    style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                TextButton.icon(
                  onPressed: _showLinkPrayerDialog,
                  icon: Icon(Icons.add, size: AppTheme.headingMedium.fontSize),
                  label: Text(l10n(context).add),
                  style: TextButton.styleFrom(
                    foregroundColor: AppTheme.rosePink,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
            if (prayerIds.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: AppTheme.spacing8),
                child: Text(
                  l10n(context).noLinkedPrayersYet,
                  style: TextStyle(
                    fontSize: 14,
                    color: context.mutedText,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              )
            else
              ...prayerIds.map((prayerId) => _LinkedPrayerTile(
                    prayerId: prayerId,
                    onRemove: () => _unlinkPrayer(prayerId),
                    onTap: () =>
                        Navigator.of(context, rootNavigator: true).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            PrayerDetailScreen(prayerId: prayerId),
                      ),
                    ),
                  )),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final promiseAsync = ref.watch(promiseByIdProvider(widget.promiseId));

    return promiseAsync.when(
      loading: () => Scaffold(
        appBar: AppBar(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          elevation: 0,
        ),
        body: const DetailPageSkeleton(),
      ),
      error: (error, _) => Scaffold(
        appBar: AppBar(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          elevation: 0,
        ),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline,
                  size: 48, color: Theme.of(context).colorScheme.error),
              const SizedBox(height: AppTheme.spacing16),
              Text(UserFacingError.forLoad(error)),
              const SizedBox(height: AppTheme.spacing16),
              ElevatedButton(
                onPressed: () => ref.invalidate(promiseByIdProvider(widget.promiseId)),
                child: Text(l10n(context).retry),
              ),
            ],
          ),
        ),
      ),
      data: (promise) {
        if (promise == null) {
          return Scaffold(
            appBar: AppBar(
              backgroundColor: Theme.of(context).scaffoldBackgroundColor,
              elevation: 0,
            ),
            body: Center(child: Text(l10n(context).promiseNotFound)),
          );
        }

        return _buildPromiseDetail(context, promise);
      },
    );
  }

  Widget _buildPromiseDetail(BuildContext context, PromiseModel promise) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        leading: IconButton(
          tooltip: l10n(context).actionBack,
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            tooltip: l10n(context).editPromise,
            icon: const Icon(Icons.edit_outlined),
            onPressed: () async {
              await context.push('/promises/${widget.promiseId}/edit');
              ref.invalidate(promiseByIdProvider(widget.promiseId));
            },
          ),
          IconButton(
            tooltip: promise.isFavorite ? 'Remove from favourites' : 'Add to favourites',
            icon: Icon(
              promise.isFavorite ? Icons.favorite : Icons.favorite_border,
              color: promise.isFavorite ? Colors.red : null,
            ),
            onPressed: _toggleFavorite,
          ),
          IconButton(
            tooltip: l10n(context).deletePromise,
            icon: const Icon(Icons.delete_outline),
            onPressed: _showDeleteConfirmation,
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: AppTheme.paddingAllBase,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                promise.reference,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              _buildTagsFromProviders(),
              const SizedBox(height: AppTheme.spacing16),
              Card(
                child: Padding(
                  padding: AppTheme.paddingAllBase,
                  child: Text(
                    promise.content,
                    style: const TextStyle(
                      fontStyle: FontStyle.italic,
                      fontSize: 16,
                      height: 1.5,
                    ),
                  ),
                ),
              ),
              ..._buildNotesSection(context, promise.notes),
              _buildConditionsFromProviders(),
              _buildLinkedPrayersSection(),
            ],
          ),
        ),
      ),
    );
  }
}

/// A single linked prayer tile that resolves the prayer title reactively.
class _LinkedPrayerTile extends ConsumerWidget {
  final String prayerId;
  final VoidCallback onRemove;
  final VoidCallback onTap;

  const _LinkedPrayerTile({
    required this.prayerId,
    required this.onRemove,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prayerAsync = ref.watch(prayerByIdProvider(prayerId));

    return prayerAsync.when(
      loading: () => const ListTileSkeleton(hasLeading: false),
      error: (_, _) => const SizedBox.shrink(),
      data: (prayer) {
        if (prayer == null || prayer.isDeleted) return const SizedBox.shrink();
        return ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.volunteer_activism,
              size: AppTheme.iconBase, color: AppTheme.rosePink),
          title: Text(
            prayer.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: IconButton(
            tooltip: l10n(context).remove,
            icon: Icon(Icons.close, size: 18, color: context.hintText),
            onPressed: onRemove,
            visualDensity: VisualDensity.compact,
          ),
          onTap: onTap,
        );
      },
    );
  }
}
