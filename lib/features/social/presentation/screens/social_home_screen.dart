import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/navigation/routes.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/sync/providers/sync_providers.dart';
import '../../../groups/presentation/widgets/group_card.dart';
import '../../../groups/presentation/widgets/join_group_dialog.dart';

/// Hub screen for the Social tab — merges People, Friends, and Groups.
///
/// Layout (priority order):
/// 1. Friends summary + pending requests badge
/// 2. Groups list with content counts
/// 3. People (prayer contacts) with "See all" link
class SocialHomeScreen extends ConsumerWidget {
  const SocialHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: Text(
          'Social',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.person_outline, color: Colors.grey.shade600),
            tooltip: 'Profile',
            onPressed: () => context.push(Routes.socialProfileSettings),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          // ── Friends Section ──
          _SectionHeader(
            title: 'Friends',
            onSeeAll: () => context.push(Routes.socialFriends),
          ),
          const SizedBox(height: 8),
          _FriendsSummaryRow(ref: ref),

          const SizedBox(height: 24),

          // ── Groups Section ──
          _SectionHeader(
            title: 'Groups',
            onSeeAll: () => context.push(Routes.socialGroups),
          ),
          const SizedBox(height: 8),
          _GroupsList(ref: ref),

          const SizedBox(height: 24),

          // ── People Section ──
          _SectionHeader(
            title: 'People',
            onSeeAll: () => context.push(Routes.socialPeople),
          ),
          const SizedBox(height: 8),
          _PeoplePreview(ref: ref),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final VoidCallback onSeeAll;

  const _SectionHeader({required this.title, required this.onSeeAll});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
        TextButton(
          onPressed: onSeeAll,
          style: TextButton.styleFrom(foregroundColor: AppTheme.teal),
          child: const Text('See all'),
        ),
      ],
    );
  }
}

class _FriendsSummaryRow extends StatelessWidget {
  final WidgetRef ref;

  const _FriendsSummaryRow({required this.ref});

  @override
  Widget build(BuildContext context) {
    final friendCount = ref.watch(friendCountProvider);
    final pendingCount = ref.watch(pendingRequestCountProvider);

    return Row(
      children: [
        Expanded(
          child: Card(
            child: InkWell(
              onTap: () => context.push(Routes.socialFriends),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    const Icon(Icons.people_outline, size: 28),
                    const SizedBox(height: 8),
                    Text(
                      friendCount.when(
                        data: (c) => '$c',
                        loading: () => '...',
                        error: (e, _) => '–',
                      ),
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const Text('Friends'),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Card(
            child: InkWell(
              onTap: () => context.push(Routes.socialFriendRequests),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Badge(
                      isLabelVisible: pendingCount.valueOrNull != null &&
                          pendingCount.valueOrNull! > 0,
                      label: Text('${pendingCount.valueOrNull ?? 0}'),
                      child: const Icon(Icons.person_add_outlined, size: 28),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Requests',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    pendingCount.when(
                      data: (c) => Text(c > 0 ? '$c pending' : 'None'),
                      loading: () => const Text('...'),
                      error: (_, _) => const Text('–'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _GroupsList extends StatelessWidget {
  final WidgetRef ref;

  const _GroupsList({required this.ref});

  @override
  Widget build(BuildContext context) {
    final groupsAsync = ref.watch(groupsListProvider);

    return groupsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Text('Error loading groups: $error'),
      data: (groups) {
        if (groups.isEmpty) {
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  const Icon(Icons.group_outlined, size: 48, color: Colors.grey),
                  const SizedBox(height: 12),
                  const Text('No groups yet'),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      FilledButton.tonal(
                        onPressed: () => context.push(Routes.socialCreateGroup),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.teal.withValues(alpha: 0.15),
                          foregroundColor: AppTheme.teal,
                        ),
                        child: const Text('Create'),
                      ),
                      const SizedBox(width: 12),
                      OutlinedButton(
                        onPressed: () => showJoinGroupDialog(context, ref),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.teal,
                          side: const BorderSide(color: AppTheme.teal),
                        ),
                        child: const Text('Join'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        }

        // Show up to 3 groups, then "See all"
        final displayGroups = groups.take(3).toList();
        return Column(
          children: [
            for (final group in displayGroups)
              GroupCard(
                group: group,
                onTap: () => context.push('/social/groups/${group.id}'),
              ),
            if (groups.length > 3)
              TextButton(
                onPressed: () => context.push(Routes.socialGroups),
                style: TextButton.styleFrom(foregroundColor: AppTheme.teal),
                child: Text('See all ${groups.length} groups'),
              ),
          ],
        );
      },
    );
  }
}

class _PeoplePreview extends StatelessWidget {
  final WidgetRef ref;

  const _PeoplePreview({required this.ref});

  @override
  Widget build(BuildContext context) {
    final peopleAsync = ref.watch(peopleStreamProvider);

    return peopleAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Text('Error: $error'),
      data: (people) {
        if (people.isEmpty) {
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  const Icon(Icons.person_outline, size: 48, color: Colors.grey),
                  const SizedBox(height: 12),
                  const Text('No people added yet'),
                  const SizedBox(height: 8),
                  FilledButton.tonal(
                    onPressed: () => context.push(Routes.socialPersonNew),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.teal.withValues(alpha: 0.15),
                      foregroundColor: AppTheme.teal,
                    ),
                    child: const Text('Add person'),
                  ),
                ],
              ),
            ),
          );
        }

        // Show up to 5 people
        final displayPeople = people.take(5).toList();
        return Column(
          children: [
            for (final person in displayPeople)
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: AppTheme.teal,
                  child: Text(
                    person.name.isNotEmpty ? person.name[0].toUpperCase() : '?',
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
                title: Text(person.name),
                subtitle: person.relation.isNotEmpty ? Text(person.relation) : null,
                onTap: () => context.push('/social/people/${person.id}'),
              ),
            if (people.length > 5)
              TextButton(
                onPressed: () => context.push(Routes.socialPeople),
                style: TextButton.styleFrom(foregroundColor: AppTheme.teal),
                child: Text('See all ${people.length} people'),
              ),
          ],
        );
      },
    );
  }
}
