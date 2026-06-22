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
    final shell = StatefulNavigationShell.of(context);
    final promisesAsync = _showingTrash
        ? ref.watch(trashedPromisesStreamProvider)
        : ref.watch(promisesStreamProvider);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && context.mounted) {
          shell.goBranch(0); // Switch to Home tab
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
                foregroundColor: Colors.white,
                onPressed: () => context.push('/promises/new'),
                child: const Icon(Icons.add),
              ),
        body: promisesAsync.when(
          loading: () => const ListTileSkeletonList(count: 6, hasLeading: false),
          error: (error, stack) => Center(child: Text('Error: $error')),
          data: (promises) {
            if (promises.isEmpty) {
              return _buildEmptyState(context);
            }

            return ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: promises.length,
              itemBuilder: (context, index) {
                final promise = promises[index];
                if (_showingTrash) {
                  return _TrashedPromiseListTile(promise: promise);
                }
                return Slidable(
                  key: Key(promise.id),
                  endActionPane: ActionPane(
                    motion: const DrawerMotion(),
                    extentRatio: 0.2,
                    children: [
                      SlidableAction(
                        onPressed: (ctx) async {
                          final shouldDelete = await _showDeleteConfirmation(context);
                          if (!context.mounted) return;
                          if (shouldDelete) {
                            _deletePromise(context, ref, promise.id);
                          }
                        },
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        icon: Icons.delete,
                        borderRadius: BorderRadius.circular(12),
                      ),
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
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.delete_outline, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text(
              'Trash is empty',
              style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
            ),
          ],
        ),
      );
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.book_outlined, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              'No promises yet',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w500,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Tap + to add your first Bible promise',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<bool> _showDeleteConfirmation(BuildContext context) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Move to Trash'),
            content:
                const Text('Are you sure you want to move this promise to trash?'),
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

  void _deletePromise(BuildContext context, WidgetRef ref, String promiseId) {
    final repository = ref.read(promiseRepositoryProvider);
    repository.trashPromise(promiseId);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Moved to trash'),
        behavior: SnackBarBehavior.floating,
      ),
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
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        promise.preview.isNotEmpty ? promise.preview : promise.content,
        style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.restore),
            tooltip: 'Restore',
            onPressed: () async {
              try {
                await ref.read(promiseRepositoryProvider).restorePromise(promise.id);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Promise restored'),
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
                          'This promise will be permanently deleted. This cannot be undone.'),
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
                      .read(promiseRepositoryProvider)
                      .deletePromise(promise.id);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Promise permanently deleted'),
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
