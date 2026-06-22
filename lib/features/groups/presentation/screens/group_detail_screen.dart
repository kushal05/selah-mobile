import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:share_plus/share_plus.dart';

import '../../../../core/navigation/routes.dart';
import '../../../../core/domain/enums/prayer_enums.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/sync/models/group_feed_item.dart';
import '../../../../core/sync/models/prayer_model.dart';
import '../../../../core/sync/providers/sync_providers.dart';
import '../../../prayers/presentation/screens/prayer_detail_screen.dart';
import '../../../prayers/presentation/screens/add_prayer_screen.dart';
import '../../../../shared/widgets/skeletons/skeletons.dart';
import '../widgets/announcement_card.dart';

/// Group detail screen with tabs for prayers, announcements, and info
class GroupDetailScreen extends ConsumerStatefulWidget {
  final String groupId;

  const GroupDetailScreen({super.key, required this.groupId});

  @override
  ConsumerState<GroupDetailScreen> createState() => _GroupDetailScreenState();
}

class _GroupDetailScreenState extends ConsumerState<GroupDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final groupAsync = ref.watch(groupByIdProvider(widget.groupId));
    final membersAsync = ref.watch(groupMembersProvider(widget.groupId));

    return groupAsync.when(
      loading: () =>
          const Scaffold(body: DetailPageSkeleton()),
      error: (error, stack) =>
          Scaffold(body: Center(child: Text('Error: $error'))),
      data: (group) {
        if (group == null) {
          return const Scaffold(
            body: Center(child: Text('Group not found')),
          );
        }

        return Scaffold(
          appBar: AppBar(
            title: Text(group.name),
            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            elevation: 0,
            actions: [
              membersAsync.when(
                loading: () => const SizedBox.shrink(),
                error: (_, _) => const SizedBox.shrink(),
                data: (members) {
                  final authService = ref.read(authServiceProvider);
                  final userId = authService.currentUserId ?? '';
                  final currentMember = members
                      .where((m) => m.memberUserId == userId)
                      .toList();
                  final isAdmin = currentMember.isNotEmpty &&
                      currentMember.first.isAdmin;

                  if (!isAdmin) return const SizedBox.shrink();

                  return PopupMenuButton<String>(
                    onSelected: (value) {
                      switch (value) {
                        case 'members':
                          context.push(
                              '/groups/${widget.groupId}/members');
                        case 'share':
                          _showShareCode(context, group.joinCode);
                        case 'edit':
                          _showEditDialog(context);
                        case 'delete':
                          _confirmDelete(context);
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'members',
                        child: Text('Manage Members'),
                      ),
                      const PopupMenuItem(
                        value: 'share',
                        child: Text('Share Join Code'),
                      ),
                      const PopupMenuItem(
                        value: 'edit',
                        child: Text('Edit Group'),
                      ),
                      const PopupMenuDivider(),
                      PopupMenuItem(
                        value: 'delete',
                        child: Text(
                          'Delete Group',
                          style: TextStyle(color: Colors.red.shade600),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
            bottom: TabBar(
              controller: _tabController,
              labelColor: AppTheme.teal,
              unselectedLabelColor: Colors.grey.shade600,
              indicatorColor: AppTheme.teal,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: const [
                Tab(text: 'Overview'),
                Tab(text: 'Feed'),
                Tab(text: 'Prayers'),
                Tab(text: 'Announcements'),
                Tab(text: 'Members'),
                Tab(text: 'Info'),
              ],
            ),
          ),
          body: TabBarView(
            controller: _tabController,
            children: [
              _OverviewTab(groupId: widget.groupId),
              _FeedTab(groupId: widget.groupId),
              _PrayersTab(groupId: widget.groupId),
              _AnnouncementsTab(groupId: widget.groupId),
              _MembersTab(groupId: widget.groupId),
              _InfoTab(groupId: widget.groupId),
            ],
          ),
        );
      },
    );
  }

  void _showShareCode(BuildContext context, String joinCode) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Group Join Code'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Share this code with others to invite them:'),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                color: AppTheme.teal.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                joinCode,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 4,
                  color: AppTheme.teal,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: joinCode));
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Code copied to clipboard'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            child: const Text('Copy'),
          ),
          TextButton(
            onPressed: () {
              final link = Routes.groupDeepLink(widget.groupId);
              Share.share(
                'Join our group!\n\nCode: $joinCode\n$link',
              );
            },
            child: const Text('Share'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  Future<void> _showEditDialog(BuildContext context) async {
    final groupAsync = ref.read(groupByIdProvider(widget.groupId));
    final group = groupAsync.valueOrNull;
    if (group == null) return;

    final nameController = TextEditingController(text: group.name);
    final descController = TextEditingController(text: group.description);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Group'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: InputDecoration(
                labelText: 'Group Name',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: descController,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: 'Description',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      nameController.dispose();
      descController.dispose();
      return;
    }

    try {
      final api = ref.read(groupsApiServiceProvider);
      await api.updateGroup(
        groupId: widget.groupId,
        name: nameController.text.trim(),
        description: descController.text.trim(),
      );
      ref.invalidate(groupByIdProvider(widget.groupId));
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      nameController.dispose();
      descController.dispose();
    }
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Group'),
        content: const Text(
          'Are you sure you want to delete this group? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final api = ref.read(groupsApiServiceProvider);
      await api.deleteGroup(widget.groupId);
      ref.invalidate(groupsListProvider);
      if (context.mounted) context.pop();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }
}

/// Overview tab showing group summary with quick stats
class _OverviewTab extends ConsumerWidget {
  final String groupId;
  const _OverviewTab({required this.groupId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupAsync = ref.watch(groupByIdProvider(groupId));
    final membersAsync = ref.watch(groupMembersProvider(groupId));
    final prayersAsync = ref.watch(groupPrayersProvider(groupId));
    final announcementsAsync = ref.watch(groupAnnouncementsProvider(groupId));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Group header card
          groupAsync.when(
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
            data: (group) {
              if (group == null) return const SizedBox.shrink();
              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor:
                          AppTheme.teal.withValues(alpha: 0.1),
                      child: Text(
                        group.initials,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.teal,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            group.name,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (group.description.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              group.description,
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey.shade600,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),

          const SizedBox(height: 16),

          // Quick stats row
          Row(
            children: [
              _OverviewStatCard(
                icon: Icons.people_outline,
                label: 'Members',
                count: membersAsync.whenOrNull(
                        data: (members) => members.length) ??
                    0,
              ),
              const SizedBox(width: 12),
              _OverviewStatCard(
                icon: Icons.volunteer_activism,
                label: 'Prayers',
                count: prayersAsync.whenOrNull(
                        data: (prayers) => prayers.length) ??
                    0,
              ),
              const SizedBox(width: 12),
              _OverviewStatCard(
                icon: Icons.campaign_outlined,
                label: 'Posts',
                count: announcementsAsync.whenOrNull(
                        data: (announcements) => announcements.length) ??
                    0,
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Pinned announcements
          announcementsAsync.when(
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
            data: (announcements) {
              final pinned =
                  announcements.where((a) => a.pinned).toList();
              if (pinned.isEmpty) return const SizedBox.shrink();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.push_pin,
                          size: 16, color: Colors.grey.shade600),
                      const SizedBox(width: 4),
                      Text(
                        'Pinned',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ...pinned.map((a) => Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Theme.of(context).cardColor,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              a.title,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (a.content.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                a.content,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ],
                        ),
                      )),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _OverviewStatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final int count;

  const _OverviewStatCard({
    required this.icon,
    required this.label,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(icon, size: 24, color: AppTheme.teal),
            const SizedBox(height: 8),
            Text(
              count.toString(),
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Prayers tab showing group prayers with completion stats
class _PrayersTab extends ConsumerStatefulWidget {
  final String groupId;
  const _PrayersTab({required this.groupId});

  @override
  ConsumerState<_PrayersTab> createState() => _PrayersTabState();
}

class _PrayersTabState extends ConsumerState<_PrayersTab> {
  @override
  Widget build(BuildContext context) {
    final groupPrayersAsync = ref.watch(groupPrayersProvider(widget.groupId));
    final allPrayersAsync = ref.watch(prayersStreamProvider);

    return Stack(
      children: [
        groupPrayersAsync.when(
          loading: () => const ListTileSkeletonList(count: 5, hasLeading: false),
          error: (error, stack) => Center(child: Text('Error: $error')),
          data: (groupPrayers) {
            if (groupPrayers.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.volunteer_activism,
                          size: 48, color: Colors.grey.shade400),
                      const SizedBox(height: 16),
                      Text(
                        'No prayers shared yet',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Tap + to add a prayer to this group',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade500,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              );
            }

            // Build prayer lookup map from all prayers
            final allPrayers =
                allPrayersAsync.valueOrNull ?? <PrayerModel>[];
            final prayerMap = {for (final p in allPrayers) p.id: p};

            // Calculate completion stats
            final resolved = groupPrayers
                .map((gp) => prayerMap[gp.prayerId])
                .whereType<PrayerModel>()
                .toList();
            final activeCount = resolved
                .where((p) => p.status == PrayerStatus.active)
                .length;
            final answeredCount = resolved
                .where((p) => p.status == PrayerStatus.answered)
                .length;
            final archivedCount = resolved
                .where((p) => p.status == PrayerStatus.archived)
                .length;

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Stats summary row
                Row(
                  children: [
                    _StatChip(
                        label: 'Active',
                        count: activeCount,
                        color: AppTheme.teal),
                    const SizedBox(width: 8),
                    _StatChip(
                        label: 'Answered',
                        count: answeredCount,
                        color: AppTheme.teal),
                    const SizedBox(width: 8),
                    _StatChip(
                        label: 'Archived',
                        count: archivedCount,
                        color: AppTheme.mutedGrey),
                  ],
                ),
                const SizedBox(height: 16),

                // Prayer list
                ...groupPrayers.map((gp) {
                  final prayer = prayerMap[gp.prayerId];
                  final title = prayer?.title ?? 'Prayer';
                  final status = prayer?.status;

                  return GestureDetector(
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            PrayerDetailScreen(prayerId: gp.prayerId),
                      ),
                    ),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Theme.of(context).cardColor,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.volunteer_activism,
                              color: AppTheme.teal
                                  .withValues(alpha: 0.7)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Added by ${gp.addedByUsername}',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (status != null) _buildStatusBadge(status),
                          const SizedBox(width: 4),
                          Icon(Icons.chevron_right,
                              color: Colors.grey.shade400, size: 20),
                        ],
                      ),
                    ),
                  );
                }),
                // Bottom spacing for FAB
                const SizedBox(height: 72),
              ],
            );
          },
        ),
        Positioned(
          bottom: 16,
          right: 16,
          child: FloatingActionButton(
            heroTag: 'add_group_prayer',
            onPressed: () => _showAddPrayerOptions(context),
            backgroundColor: AppTheme.teal,
            child: const Icon(Icons.add, color: Colors.white),
          ),
        ),
      ],
    );
  }

  void _showAddPrayerOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Add Prayer to Group',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.teal.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.add,
                      color: AppTheme.teal, size: 20),
                ),
                title: const Text('Create New Prayer'),
                subtitle: Text(
                  'Create a new prayer and add it to this group',
                  style: TextStyle(
                      fontSize: 12, color: Colors.grey.shade600),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _createNewPrayerForGroup(context);
                },
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.teal.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.playlist_add,
                      color: AppTheme.teal, size: 20),
                ),
                title: const Text('Add Existing Prayer'),
                subtitle: Text(
                  'Choose from your personal prayers',
                  style: TextStyle(
                      fontSize: 12, color: Colors.grey.shade600),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _showExistingPrayersPicker(context);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Future<void> _createNewPrayerForGroup(BuildContext context) async {
    // Navigate to add prayer screen, wait for result
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AddPrayerScreen()),
    );

    if (!context.mounted) return;

    // After returning, get the user's most recent prayer and offer to add it
    final prayers =
        ref.read(prayersStreamProvider).valueOrNull ?? <PrayerModel>[];
    if (prayers.isEmpty) return;

    // Get the newest prayer (sorted by updatedAt DESC)
    final newest = prayers.first;

    final addToGroup = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add to Group?'),
        content: Text(
          'Would you like to add "${newest.title}" to this group?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('No'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Yes, Add'),
          ),
        ],
      ),
    );

    if (addToGroup == true && mounted) {
      await _addPrayerToGroup(newest.id);
    }
  }

  Future<void> _showExistingPrayersPicker(BuildContext context) async {
    final allPrayers =
        ref.read(prayersStreamProvider).valueOrNull ?? <PrayerModel>[];
    final groupPrayers =
        ref.read(groupPrayersProvider(widget.groupId)).valueOrNull ?? [];
    final existingPrayerIds =
        groupPrayers.map((gp) => gp.prayerId).toSet();

    // Filter out prayers already in the group
    final available = allPrayers
        .where((p) => !existingPrayerIds.contains(p.id))
        .toList();

    if (available.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('All your prayers are already in this group'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    final selected = await showModalBottomSheet<PrayerModel>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          maxChildSize: 0.85,
          minChildSize: 0.3,
          builder: (context, scrollController) {
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Select a Prayer',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView.builder(
                    controller: scrollController,
                    itemCount: available.length,
                    itemBuilder: (context, index) {
                      final prayer = available[index];
                      return ListTile(
                        leading: Icon(
                          Icons.volunteer_activism,
                          color: AppTheme.teal
                              .withValues(alpha: 0.7),
                        ),
                        title: Text(
                          prayer.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          prayer.status.displayName,
                          style: TextStyle(
                            fontSize: 12,
                            color: _statusColor(prayer.status),
                          ),
                        ),
                        trailing: const Icon(
                            Icons.add_circle_outline,
                            color: AppTheme.teal),
                        onTap: () => Navigator.pop(context, prayer),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    if (selected != null && mounted) {
      await _addPrayerToGroup(selected.id);
    }
  }

  Color _statusColor(PrayerStatus status) {
    return switch (status) {
      PrayerStatus.active => AppTheme.brandBlue,
      PrayerStatus.answered => AppTheme.teal,
      PrayerStatus.archived => AppTheme.mutedGrey,
    };
  }

  Future<void> _addPrayerToGroup(String prayerId) async {
    try {
      final api = ref.read(groupContentApiServiceProvider);
      await api.addGroupPrayer(
        groupId: widget.groupId,
        prayerId: prayerId,
      );
      ref.invalidate(groupPrayersProvider(widget.groupId));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Prayer added to group'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to add prayer: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Widget _buildStatusBadge(PrayerStatus status) {
    final (String label, Color color) = switch (status) {
      PrayerStatus.active => ('Active', AppTheme.brandBlue),
      PrayerStatus.answered => ('Answered', AppTheme.teal),
      PrayerStatus.archived => ('Archived', AppTheme.mutedGrey),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final int count;
  final Color color;

  const _StatChip({
    required this.label,
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Text(
              count.toString(),
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: color.withValues(alpha: 0.8),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Announcements tab
class _AnnouncementsTab extends ConsumerStatefulWidget {
  final String groupId;
  const _AnnouncementsTab({required this.groupId});

  @override
  ConsumerState<_AnnouncementsTab> createState() => _AnnouncementsTabState();
}

class _AnnouncementsTabState extends ConsumerState<_AnnouncementsTab> {
  @override
  Widget build(BuildContext context) {
    final announcementsAsync =
        ref.watch(groupAnnouncementsProvider(widget.groupId));
    final membersAsync = ref.watch(groupMembersProvider(widget.groupId));

    return announcementsAsync.when(
      loading: () => const Column(children: [FeedItemSkeleton(), FeedItemSkeleton(), FeedItemSkeleton()]),
      error: (error, stack) => Center(child: Text('Error: $error')),
      data: (announcements) {
        final authService = ref.read(authServiceProvider);
        final userId = authService.currentUserId ?? '';

        final canManage = membersAsync.whenOrNull(
              data: (members) {
                final current = members
                    .where((m) => m.memberUserId == userId)
                    .toList();
                return current.isNotEmpty && current.first.canManage;
              },
            ) ??
            false;

        // Sort: pinned announcements first, then by creation date (newest first)
        final sorted = List.of(announcements)
          ..sort((a, b) {
            if (a.pinned && !b.pinned) return -1;
            if (!a.pinned && b.pinned) return 1;
            return b.createdAt.compareTo(a.createdAt);
          });

        return Stack(
          children: [
            if (sorted.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.campaign_outlined,
                          size: 48, color: Colors.grey.shade400),
                      const SizedBox(height: 16),
                      Text(
                        'No announcements',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: sorted.length,
                itemBuilder: (context, index) {
                  final announcement = sorted[index];
                  return AnnouncementCard(
                    announcement: announcement,
                    canEdit: canManage,
                    onEdit: () =>
                        _editAnnouncement(announcement.id, announcement.title, announcement.content),
                    onTogglePin: () =>
                        _togglePin(announcement.id, !announcement.pinned),
                    onDelete: () => _deleteAnnouncement(announcement.id),
                  );
                },
              ),
            if (canManage)
              Positioned(
                bottom: 16,
                right: 16,
                child: FloatingActionButton(
                  heroTag: 'add_announcement',
                  onPressed: _createAnnouncement,
                  backgroundColor: AppTheme.teal,
                  child: const Icon(Icons.add, color: Colors.white),
                ),
              ),
          ],
        );
      },
    );
  }

  Future<void> _createAnnouncement() async {
    final titleController = TextEditingController();
    final contentController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New Announcement'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleController,
              decoration: InputDecoration(
                labelText: 'Title',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: contentController,
              maxLines: 4,
              decoration: InputDecoration(
                labelText: 'Content (optional)',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Post'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      titleController.dispose();
      contentController.dispose();
      return;
    }

    final title = titleController.text.trim();
    if (title.isEmpty) {
      titleController.dispose();
      contentController.dispose();
      return;
    }

    try {
      final api = ref.read(groupContentApiServiceProvider);
      await api.createAnnouncement(
        groupId: widget.groupId,
        title: title,
        content: contentController.text.trim(),
      );
      ref.invalidate(groupAnnouncementsProvider(widget.groupId));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to create announcement: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      titleController.dispose();
      contentController.dispose();
    }
  }

  Future<void> _editAnnouncement(
      String id, String currentTitle, String currentContent) async {
    final titleController = TextEditingController(text: currentTitle);
    final contentController = TextEditingController(text: currentContent);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Announcement'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleController,
              decoration: InputDecoration(
                labelText: 'Title',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: contentController,
              maxLines: 4,
              decoration: InputDecoration(
                labelText: 'Content',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      titleController.dispose();
      contentController.dispose();
      return;
    }

    try {
      final api = ref.read(groupContentApiServiceProvider);
      await api.updateAnnouncement(
        groupId: widget.groupId,
        announcementId: id,
        title: titleController.text.trim(),
        content: contentController.text.trim(),
      );
      ref.invalidate(groupAnnouncementsProvider(widget.groupId));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      titleController.dispose();
      contentController.dispose();
    }
  }

  Future<void> _togglePin(String id, bool pinned) async {
    try {
      final api = ref.read(groupContentApiServiceProvider);
      await api.updateAnnouncement(
        groupId: widget.groupId,
        announcementId: id,
        pinned: pinned,
      );
      ref.invalidate(groupAnnouncementsProvider(widget.groupId));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _deleteAnnouncement(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Announcement'),
        content: const Text('Are you sure you want to delete this announcement?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final api = ref.read(groupContentApiServiceProvider);
      await api.deleteAnnouncement(
        groupId: widget.groupId,
        announcementId: id,
      );
      ref.invalidate(groupAnnouncementsProvider(widget.groupId));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }
}

/// Members tab showing group members list
class _MembersTab extends ConsumerWidget {
  final String groupId;
  const _MembersTab({required this.groupId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final membersAsync = ref.watch(groupMembersProvider(groupId));

    return membersAsync.when(
      loading: () => const Column(
          children: [ListTileSkeleton(), ListTileSkeleton(), ListTileSkeleton()]),
      error: (error, _) => Center(child: Text('Error: $error')),
      data: (members) {
        if (members.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.people_outline, size: 48, color: Colors.grey.shade400),
                const SizedBox(height: 16),
                Text(
                  'No members yet',
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

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: members.length,
          itemBuilder: (context, index) {
            final member = members[index];
            final initial = member.memberUsername.isNotEmpty
                ? member.memberUsername[0].toUpperCase()
                : '?';
            final displayName = member.memberDisplayName.isNotEmpty
                ? member.memberDisplayName
                : member.memberUsername;

            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor:
                        AppTheme.teal.withValues(alpha: 0.1),
                    child: Text(
                      initial,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.teal,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displayName,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          '@${member.memberUsername}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: member.isAdmin
                          ? AppTheme.teal.withValues(alpha: 0.1)
                          : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      member.role.displayName,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: member.isAdmin
                            ? AppTheme.teal
                            : Colors.grey.shade600,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

/// Info tab showing group details and members
class _InfoTab extends ConsumerWidget {
  final String groupId;
  const _InfoTab({required this.groupId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupAsync = ref.watch(groupByIdProvider(groupId));
    final membersAsync = ref.watch(groupMembersProvider(groupId));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Group info card
          groupAsync.when(
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
            data: (group) {
              if (group == null) return const SizedBox.shrink();
              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 28,
                          backgroundColor: AppTheme.teal
                              .withValues(alpha: 0.1),
                          child: Text(
                            group.initials,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.teal,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                group.name,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  group.groupType.displayName,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  group.joinPolicy.displayName,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (group.description.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        group.description,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade700,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),

          const SizedBox(height: 24),

          // Members section
          const Text(
            'Members',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          membersAsync.when(
            loading: () => const Column(children: [ListTileSkeleton(), ListTileSkeleton(), ListTileSkeleton()]),
            error: (error, stack) => Text('Error: $error'),
            data: (members) {
              return Column(
                children: members.map((member) {
                  final initial = member.memberUsername.isNotEmpty
                      ? member.memberUsername[0].toUpperCase()
                      : '?';
                  final displayName = member.memberDisplayName.isNotEmpty
                      ? member.memberDisplayName
                      : member.memberUsername;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 20,
                          backgroundColor: AppTheme.teal
                              .withValues(alpha: 0.1),
                          child: Text(
                            initial,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.teal,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                displayName,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                '@${member.memberUsername}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: member.isAdmin
                                ? AppTheme.teal
                                    .withValues(alpha: 0.1)
                                : Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            member.role.displayName,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: member.isAdmin
                                  ? AppTheme.teal
                                  : Colors.grey.shade600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              );
            },
          ),
          const SizedBox(height: 24),
          membersAsync.when(
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
            data: (members) {
              final currentUserId = ref.watch(currentUserIdProvider);
              final isMember =
                  members.any((m) => m.memberUserId == currentUserId);
              if (!isMember) return const SizedBox.shrink();

              return SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () =>
                      _confirmLeaveGroup(context, ref, groupId, currentUserId),
                  icon: const Icon(Icons.exit_to_app),
                  label: const Text('Leave Group'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red.shade700,
                    side: BorderSide(color: Colors.red.shade200),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _confirmLeaveGroup(
    BuildContext context,
    WidgetRef ref,
    String groupId,
    String currentUserId,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Leave Group'),
        content: const Text('Are you sure you want to leave this group?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Leave'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await ref.read(groupsApiServiceProvider).leaveGroup(groupId);
      ref.invalidate(groupsListProvider);
      ref.invalidate(groupCountProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('You left the group'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        context.pop();
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to leave group: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }
}

/// Feed tab — merged timeline of prayers and announcements sorted by recency.
class _FeedTab extends ConsumerWidget {
  final String groupId;
  const _FeedTab({required this.groupId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feedAsync = ref.watch(groupFeedProvider(groupId));
    final theme = Theme.of(context);

    return feedAsync.when(
      loading: () => const Column(
        children: [
          FeedItemSkeleton(),
          FeedItemSkeleton(),
          FeedItemSkeleton(),
        ],
      ),
      error: (error, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 48, color: Colors.grey.shade400),
              const SizedBox(height: 16),
              Text('Could not load feed', style: TextStyle(color: Colors.grey.shade600)),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => ref.invalidate(groupFeedProvider(groupId)),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
      data: (items) {
        if (items.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.dynamic_feed_outlined, size: 48, color: Colors.grey.shade400),
                  const SizedBox(height: 16),
                  Text(
                    'No activity yet',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Shared prayers and announcements will appear here',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(groupFeedProvider(groupId)),
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            itemCount: items.length,
            itemBuilder: (context, index) => _FeedItemCard(item: items[index], theme: theme),
          ),
        );
      },
    );
  }
}

class _FeedItemCard extends StatelessWidget {
  final GroupFeedItem item;
  final ThemeData theme;

  const _FeedItemCard({required this.item, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.5)),
      ),
      child: item.isPrayer ? _buildPrayerItem() : _buildAnnouncementItem(),
    );
  }

  Widget _buildPrayerItem() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppTheme.teal.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.volunteer_activism, size: 18, color: AppTheme.teal),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Prayer shared',
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
              ),
              if (item.userId != null) ...[
                const SizedBox(height: 2),
                Text(
                  'by ${item.userId}',
                  style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
                ),
              ],
            ],
          ),
        ),
        _timestamp(item.createdAt),
      ],
    );
  }

  Widget _buildAnnouncementItem() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppTheme.brandPurple.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            item.pinned == true ? Icons.push_pin : Icons.campaign_outlined,
            size: 18,
            color: AppTheme.brandPurple,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.title ?? 'Announcement',
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (item.content != null && item.content!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  item.content!,
                  style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade700),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              if (item.authorUsername != null) ...[
                const SizedBox(height: 4),
                Text(
                  'by @${item.authorUsername}',
                  style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade500),
                ),
              ],
            ],
          ),
        ),
        _timestamp(item.createdAt),
      ],
    );
  }

  Widget _timestamp(int createdAt) {
    final dt = DateTime.fromMillisecondsSinceEpoch(createdAt);
    final now = DateTime.now();
    final diff = now.difference(dt);
    final String label;
    if (diff.inMinutes < 60) {
      label = '${diff.inMinutes}m';
    } else if (diff.inHours < 24) {
      label = '${diff.inHours}h';
    } else {
      label = '${diff.inDays}d';
    }
    return Text(
      label,
      style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
    );
  }
}
