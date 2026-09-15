import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/sync/providers/sync_providers.dart';
import '../../../../shared/widgets/cards/person_card.dart';
import '../../../../shared/widgets/skeletons/skeletons.dart';
import '../../../../shared/widgets/undo_snackbar.dart';
import '../../../../core/services/user_facing_error.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../../../core/theme/theme_colors.dart';
import '../../../../l10n/l10n.dart';
import '../../../../shared/widgets/swipe_action.dart';
import '../../../../core/navigation/tab_navigation.dart';

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
    final peopleAsync = _showingTrash
        ? ref.watch(trashedPeopleStreamProvider)
        : ref.watch(peopleStreamProvider);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && context.mounted) {
          goToTab(context, 0); // Switch to Home tab
        }
      },
      child: Scaffold(
        floatingActionButton: _showingTrash
            ? null
            : FloatingActionButton(
                heroTag: null,
                onPressed: () => context.push('/people/new'),
                backgroundColor: AppTheme.teal,
                foregroundColor: AppTheme.onAccent(AppTheme.teal),
                child: const Icon(Icons.add),
              ),
        body: SafeArea(
          child: peopleAsync.when(
            loading: () => const ListTileSkeletonList(count: 6),
            error: (error, stack) => Center(child: Text(UserFacingError.forLoad(error))),
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
                        buildSwipeAction(
            icon: Icons.delete,
            label: l10n(context).moveToTrash,
            accent: AppTheme.error,
            onPressed: (ctx) async {
                            final shouldDelete = await _showDeleteConfirmation(context);
                            if (!context.mounted) return;
                            if (shouldDelete) {
                              _deletePerson(context, ref, person.id);
                            }
                          },
          )
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
      return EmptyTrashState(itemsLabel: l10n(context).trashLabelPeople);
    }
    return EmptyState(
      icon: Icons.people_outline_rounded,
      title: l10n(context).noOneAddedYet,
      message: l10n(context).addThePeopleYouPrayForSoYouCanKeepTheirReque,
          accent: AppTheme.teal,
    );
  }

  Future<bool> _showDeleteConfirmation(BuildContext context) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(l10n(context).moveToTrash),
            content:
                Text(l10n(context).areYouSureYouWantToMoveThisPersonToTrash),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(l10n(context).actionCancel),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: TextButton.styleFrom(foregroundColor: context.dangerText),
                child: Text(l10n(context).moveToTrash),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _deletePerson(
      BuildContext context, WidgetRef ref, String personId) async {
    final repository = ref.read(personRepositoryProvider);
    try {
      await repository.trashPerson(personId);
    } catch (e) {
      // Without this the delete fails silently: no snackbar, no error, and
      // the row simply stays put with no explanation.
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(UserFacingError.message(e, action: 'delete this person')),
          backgroundColor: AppTheme.errorSurface,
        ),
      );
      return;
    }
    if (!context.mounted) return;
    showUndoSnackBar(
      context,
      itemLabel: 'Person',
      onUndo: () => repository.restorePerson(personId),
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
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: person.relation != null && person.relation.isNotEmpty
          ? Text(
              person.relation,
              style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.onSurfaceVariant),
            )
          : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.restore),
            tooltip: l10n(context).restore,
            onPressed: () async {
              try {
                await ref.read(personRepositoryProvider).restorePerson(person.id);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(l10n(context).personRestored),
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
                          l10n(context).thisPersonWillBePermanentlyDeletedThisCannot),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          child: Text(l10n(context).actionCancel),
                        ),
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(true),
                          style:
                              TextButton.styleFrom(foregroundColor: context.dangerText),
                          child: Text(l10n(context).actionDelete),
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
                      SnackBar(
                        content: Text(l10n(context).personPermanentlyDeleted),
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
