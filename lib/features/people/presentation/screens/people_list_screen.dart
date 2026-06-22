import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/sync/providers/sync_providers.dart';
import '../../../../shared/widgets/cards/person_card.dart';
import '../../../../shared/widgets/skeletons/skeletons.dart';

/// People list screen
class PeopleListScreen extends ConsumerStatefulWidget {
  const PeopleListScreen({super.key});

  @override
  ConsumerState<PeopleListScreen> createState() => _PeopleListScreenState();
}

class _PeopleListScreenState extends ConsumerState<PeopleListScreen> {
  bool _showingTrash = false;

  @override
  Widget build(BuildContext context) {
    final shell = StatefulNavigationShell.of(context);
    final peopleAsync = _showingTrash
        ? ref.watch(trashedPeopleStreamProvider)
        : ref.watch(peopleStreamProvider);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && context.mounted) {
          shell.goBranch(0); // Switch to Home tab
        }
      },
      child: Scaffold(
        floatingActionButton: _showingTrash
            ? null
            : FloatingActionButton(
                heroTag: null,
                onPressed: () => context.push('/people/new'),
                backgroundColor: AppTheme.teal,
                foregroundColor: Colors.white,
                child: const Icon(Icons.add),
              ),
        body: SafeArea(
          child: peopleAsync.when(
            loading: () => const ListTileSkeletonList(count: 6),
            error: (error, stack) => Center(child: Text('Error: $error')),
            data: (people) {
              if (people.isEmpty) {
                return _buildEmptyState(context);
              }

              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: people.length + 1, // +1 for header
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              _showingTrash ? 'Trash' : 'People',
                              style: const TextStyle(
                                  fontSize: 28, fontWeight: FontWeight.bold),
                            ),
                          ),
                          IconButton(
                            icon: Icon(_showingTrash
                                ? Icons.list
                                : Icons.delete_outline),
                            tooltip: _showingTrash
                                ? 'Show people'
                                : 'Show trash',
                            onPressed: () {
                              setState(() {
                                _showingTrash = !_showingTrash;
                              });
                            },
                          ),
                        ],
                      ),
                    );
                  }

                  final person = people[index - 1];
                  if (_showingTrash) {
                    return _TrashedPersonListTile(person: person);
                  }
                  return Slidable(
                    key: Key(person.id),
                    endActionPane: ActionPane(
                      motion: const DrawerMotion(),
                      extentRatio: 0.2,
                      children: [
                        SlidableAction(
                          onPressed: (ctx) async {
                            final shouldDelete = await _showDeleteConfirmation(context);
                            if (!context.mounted) return;
                            if (shouldDelete) {
                              _deletePerson(context, ref, person.id);
                            }
                          },
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                          icon: Icons.delete,
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ],
                    ),
                    child: PersonCard(
                      name: person.name,
                      relation: person.relation,
                      onTap: () => context.push('/people/${person.id}'),
                    ),
                  );
                },
              );
            },
          ),
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
            Icon(Icons.people_outline, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              'No people yet',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w500,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Tap + to add someone to pray for',
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
                const Text('Are you sure you want to move this person to trash?'),
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

  void _deletePerson(BuildContext context, WidgetRef ref, String personId) {
    final repository = ref.read(personRepositoryProvider);
    repository.trashPerson(personId);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Moved to trash'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

class _TrashedPersonListTile extends ConsumerWidget {
  final dynamic person;

  const _TrashedPersonListTile({required this.person});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      title: Text(
        person.name,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: person.relation != null && person.relation.isNotEmpty
          ? Text(
              person.relation,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            )
          : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.restore),
            tooltip: 'Restore',
            onPressed: () async {
              try {
                await ref.read(personRepositoryProvider).restorePerson(person.id);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Person restored'),
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
                          'This person will be permanently deleted. This cannot be undone.'),
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
                      .read(personRepositoryProvider)
                      .deletePerson(person.id);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Person permanently deleted'),
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
