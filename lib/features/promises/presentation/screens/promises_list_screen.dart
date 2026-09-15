import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/sync/models/promise_model.dart';
import '../../../../core/sync/providers/sync_providers.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../features/promises/domain/models/promise_conditions_codec.dart';
import '../../../../shared/widgets/cards/promise_card.dart';
import '../../../../shared/widgets/skeletons/skeletons.dart';
import '../../../../shared/widgets/undo_snackbar.dart';
import '../../../../core/services/user_facing_error.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../../../core/navigation/routes.dart';
import '../../../../shared/widgets/feature_intro.dart';
import '../../../../core/theme/theme_colors.dart';
import '../../../../l10n/l10n.dart';
import '../../../../shared/widgets/swipe_action.dart';
import '../../../../core/navigation/tab_navigation.dart';

/// Promises list screen
class PromisesListScreen extends ConsumerStatefulWidget {
  const PromisesListScreen({super.key});

  @override
  ConsumerState<PromisesListScreen> createState() => _PromisesListScreenState();
}

class _PromisesListScreenState extends ConsumerState<PromisesListScreen> {
  bool _showingTrash = false;

  @override
  Widget build(BuildContext context) {
    final promisesAsync = _showingTrash
        ? ref.watch(trashedPromisesStreamProvider)
        : ref.watch(promisesStreamProvider);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && context.mounted) {
          goToTab(context, 0); // Switch to Home tab
        }
      },
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          elevation: 0,
          automaticallyImplyLeading: false,
          title: Text(
            _showingTrash ? 'Trash' : 'Promises',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.search_rounded),
              tooltip: l10n(context).actionSearch,
              onPressed: () => context.push(Routes.search),
            ),
            IconButton(
              icon: Icon(_showingTrash ? Icons.list : Icons.delete_outline),
              tooltip: _showingTrash ? 'Show promises' : 'Show trash',
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
                backgroundColor: AppTheme.rosePink,
                foregroundColor: AppTheme.onAccent(AppTheme.rosePink),
                onPressed: () => context.push('/promises/new'),
                child: const Icon(Icons.add),
              ),
        body: promisesAsync.when(
          loading: () => const ListTileSkeletonList(count: 6, hasLeading: false),
          error: (error, stack) => Center(child: Text(UserFacingError.forLoad(error))),
          data: (promises) {
            if (promises.isEmpty) {
              return _buildEmptyState(context);
            }

            return ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: promises.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) return FeatureIntros.promises;
                final promise = promises[index - 1];
                if (_showingTrash) {
                  return _TrashedPromiseListTile(promise: promise);
                }
                return Slidable(
                  key: Key(promise.id),
                  endActionPane: ActionPane(
                    motion: const DrawerMotion(),
                    extentRatio: 0.2,
                    children: [
                      buildSwipeAction(
            icon: Icons.delete,
            label: l10n(context).moveToTrash,
            accent: AppTheme.error,
            onPressed: (ctx) async {
                          final shouldDelete = await _showDeleteConfirmation(context);
                          if (!context.mounted) return;
                          if (shouldDelete) {
                            _deletePromise(context, ref, promise.id);
                          }
                        },
          )
                    ],
                  ),
                  child: PromiseCard(
                    reference: promise.reference,
                    content: promise.content,
                    conditionCount: countPromiseConditions(promise.notes),
                    onTap: () => context.push('/promises/${promise.id}'),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    if (_showingTrash) {
      return EmptyTrashState(itemsLabel: l10n(context).trashLabelPromises);
    }
    return EmptyState(
      icon: Icons.bookmark_outline_rounded,
      title: l10n(context).noPromisesYet,
      message: l10n(context).aPromiseIsAVerseYouWantToHoldOnToSomethingGo,
          accent: AppTheme.rosePink,
    );
  }

  Future<bool> _showDeleteConfirmation(BuildContext context) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(l10n(context).moveToTrash),
            content:
                Text(l10n(context).areYouSureYouWantToMoveThisPromiseToTrash),
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

  Future<void> _deletePromise(
      BuildContext context, WidgetRef ref, String promiseId) async {
    final repository = ref.read(promiseRepositoryProvider);
    try {
      await repository.trashPromise(promiseId);
    } catch (e) {
      // Without this the delete fails silently: no snackbar, no error, and
      // the row simply stays put with no explanation.
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(UserFacingError.message(e, action: 'delete this promise')),
          backgroundColor: AppTheme.errorSurface,
        ),
      );
      return;
    }
    if (!context.mounted) return;
    showUndoSnackBar(
      context,
      itemLabel: 'Promise',
      onUndo: () => repository.restorePromise(promiseId),
    );
  }
}

class _TrashedPromiseListTile extends ConsumerWidget {
  final PromiseModel promise;

  const _TrashedPromiseListTile({required this.promise});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      title: Text(
        promise.reference,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        promise.preview.isNotEmpty ? promise.preview : promise.content,
        style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.onSurfaceVariant),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.restore),
            tooltip: l10n(context).restore,
            onPressed: () async {
              try {
                await ref.read(promiseRepositoryProvider).restorePromise(promise.id);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(l10n(context).promiseRestored),
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
                          l10n(context).thisPromiseWillBePermanentlyDeletedThisCanno),
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
                      .read(promiseRepositoryProvider)
                      .deletePromise(promise.id);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(l10n(context).promisePermanentlyDeleted),
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
