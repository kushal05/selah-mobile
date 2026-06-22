import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/domain/enums/prayer_enums.dart';
import '../../../../core/navigation/routes.dart';
import '../../../../core/sync/models/prayer_log_model.dart';
import '../../../../core/sync/models/prayer_model.dart';
import '../../../../core/sync/providers/sync_providers.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../people/presentation/screens/person_detail_screen.dart';
import '../../../people/presentation/screens/people_list_screen.dart';
import '../widgets/prayer_streak_card.dart';
import '../../../../shared/widgets/skeletons/skeletons.dart';

/// Prayers dashboard screen with real data from local database
class PrayersDashboardScreen extends ConsumerWidget {
  const PrayersDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shell = StatefulNavigationShell.of(context);
    final prayersAsync = ref.watch(prayersStreamProvider);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && context.mounted) {
          shell.goBranch(0); // Switch to Home tab
        }
      },
      child: Scaffold(
        backgroundColor: AppTheme.scaffoldGray,
        appBar: AppBar(
          backgroundColor: AppTheme.scaffoldGray,
          elevation: 0,
          automaticallyImplyLeading: false,
          title: Text(
            'Prayers',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ),
        floatingActionButton: FloatingActionButton(
          heroTag: null,
          backgroundColor: AppTheme.brandBlue,
          foregroundColor: Colors.white,
          onPressed: () => context.push('/prayers/new'),
          child: const Icon(Icons.add_rounded),
        ),
        body: prayersAsync.when(
          loading: () => const DashboardSkeleton(),
          error: (error, stack) => Center(child: Text('Error: $error')),
          data: (prayers) {
            return CustomScrollView(
              slivers: [
                // Scrollable content
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      _buildPrayTodayBanner(context),
                      const SizedBox(height: 16),
                      const PrayerStreakCard(),
                      const SizedBox(height: 24),
                      _buildCategorySection(context, ref, prayers),
                      const SizedBox(height: 24),
                      _buildPeopleSection(context, ref),
                      const SizedBox(height: 24),
                      _buildTodayActivitySection(context, ref, prayers),
                      const SizedBox(height: 24),
                      _buildPrayerHistorySection(context, ref, prayers),
                      const SizedBox(height: 24),
                      _buildGroupsSection(context),
                    ]),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildCategorySection(
      BuildContext context, WidgetRef ref, List prayers) {
    final activeCount =
        prayers.where((p) => p.status == PrayerStatus.active).length;
    final answeredCount =
        prayers.where((p) => p.status == PrayerStatus.answered).length;
    final archivedCount =
        prayers.where((p) => p.status == PrayerStatus.archived).length;
    final totalCount = prayers.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _PrayerSectionHeader(title: 'Categories'),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.5,
          children: [
            _CategoryCard(
              title: 'Active',
              count: activeCount,
              color: AppTheme.brandBlue,
              onTap: () => context.push('${Routes.prayerList}?status=active'),
            ),
            _CategoryCard(
              title: 'Answered',
              count: answeredCount,
              color: AppTheme.teal,
              onTap: () => context.push('${Routes.prayerList}?status=answered'),
            ),
            _CategoryCard(
              title: 'Archived',
              count: archivedCount,
              color: AppTheme.mutedGrey,
              onTap: () => context.push('${Routes.prayerList}?status=archived'),
            ),
            _CategoryCard(
              title: 'All Prayers',
              count: totalCount,
              color: AppTheme.brandPurple,
              onTap: () => context.push(Routes.prayerList),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _PremiumLinkTile(
          icon: Icons.chat_bubble_outline,
          label: 'Prayer Updates',
          color: AppTheme.brandBlue,
          onTap: () => context.push(Routes.prayerUpdatesFeed),
        ),
      ],
    );
  }

  Widget _buildPrayTodayBanner(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => context.push(Routes.prayerToday),
          child: Ink(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [AppTheme.brandBlue, AppTheme.brandPurple],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.wb_sunny_outlined,
                      color: Colors.white, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Pray Today',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.2,
                          ),
                        ),
                        Text(
                          'Start your daily prayer session',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.8),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: Colors.white),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPeopleSection(BuildContext context, WidgetRef ref) {
    final peopleAsync = ref.watch(prayerLinkedPeopleProvider);

    return peopleAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (people) {
        if (people.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const _PrayerSectionHeader(title: 'People'),
                TextButton(
                  onPressed: () =>
                      Navigator.of(context, rootNavigator: true).push(
                    MaterialPageRoute(
                        builder: (_) => const PeopleListScreen()),
                  ),
                  child: const Text('See All'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 72,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: people.length,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  final person = people[index];
                  final initials = person.name.isNotEmpty
                      ? person.name
                          .split(' ')
                          .where((w) => w.isNotEmpty)
                          .take(2)
                          .map((w) => w[0].toUpperCase())
                          .join()
                      : '?';
                  return GestureDetector(
                    onTap: () =>
                        Navigator.of(context, rootNavigator: true).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            PersonDetailScreen(personId: person.id),
                      ),
                    ),
                    child: Column(
                      children: [
                        CircleAvatar(
                          radius: 22,
                          backgroundColor: AppTheme.brandPurple
                              .withValues(alpha: 0.15),
                          child: Text(
                            initials,
                            style: const TextStyle(
                              color: AppTheme.brandPurple,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        SizedBox(
                          width: 56,
                          child: Text(
                            person.name.split(' ').first,
                            style: const TextStyle(fontSize: 11),
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildTodayActivitySection(
      BuildContext context, WidgetRef ref, List<PrayerModel> prayers) {
    final todayLogsAsync = ref.watch(todaysPrayerLogsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _PrayerSectionHeader(title: "Today's Activity"),
        const SizedBox(height: 12),
        todayLogsAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: [
                ListTileSkeleton(hasLeading: false),
                ListTileSkeleton(hasLeading: false),
              ],
            ),
          ),
          error: (_, _) => const SizedBox.shrink(),
          data: (logs) {
            if (logs.isEmpty) {
              return _EmptyStateCard(
                icon: Icons.history,
                message: 'No prayers logged today',
              );
            }

            // Build prayer title lookup map
            final prayerMap = {for (final p in prayers) p.id: p.title};

            return Column(
              children: [
                // Stats row
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.brandBlue.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppTheme.brandBlue.withValues(alpha: 0.12),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle_outline,
                          color: AppTheme.brandBlue),
                      const SizedBox(width: 12),
                      Text(
                        '${logs.length} prayer${logs.length == 1 ? '' : 's'} logged today',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.brandBlue,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),

                // Recent logs list
                ...logs.take(5).map((log) => _buildLogRow(
                      context,
                      log,
                      prayerMap[log.prayerId] ?? 'Unknown Prayer',
                    )),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildLogRow(
      BuildContext context, PrayerLogModel log, String prayerTitle) {
    final logTime = DateTime.fromMillisecondsSinceEpoch(log.loggedAt);
    final timeStr =
        '${logTime.hour.toString().padLeft(2, '0')}:${logTime.minute.toString().padLeft(2, '0')}';

    return InkWell(
      onTap: () => context.push('/prayers/${log.prayerId}'),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: AppTheme.teal,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    prayerTitle,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (log.note.isNotEmpty)
                    Text(
                      log.note,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            Text(
              timeStr,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPrayerHistorySection(
      BuildContext context, WidgetRef ref, List<PrayerModel> prayers) {
    final weeklyLogsAsync = ref.watch(weeklyPrayerLogsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _PrayerSectionHeader(title: 'Prayer History'),
        const SizedBox(height: 12),
        weeklyLogsAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: [
                ListTileSkeleton(hasLeading: false),
                ListTileSkeleton(hasLeading: false),
              ],
            ),
          ),
          error: (_, _) => const SizedBox.shrink(),
          data: (logs) {
            if (logs.isEmpty) {
              return _EmptyStateCard(
                icon: Icons.history,
                message: 'No prayer history this week',
              );
            }

            // Group logs by session date
            final grouped = <String, List<PrayerLogModel>>{};
            for (final log in logs) {
              grouped.putIfAbsent(log.sessionDate, () => []).add(log);
            }

            final prayerMap = {for (final p in prayers) p.id: p.title};
            final today = _todaySessionDate();

            // Sort dates descending, skip today (already shown above)
            final dates = grouped.keys
                .where((d) => d != today)
                .toList()
              ..sort((a, b) => b.compareTo(a));

            if (dates.isEmpty) {
              return _EmptyStateCard(
                icon: Icons.check_circle_outline,
                message: 'No history beyond today',
              );
            }

            // Summary
            final totalLogs =
                dates.fold<int>(0, (sum, d) => sum + grouped[d]!.length);

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.brandPurple.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppTheme.brandPurple.withValues(alpha: 0.12),
                    ),
                  ),
                  child: Text(
                    '$totalLogs prayers logged over ${dates.length} day${dates.length == 1 ? '' : 's'} this week',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AppTheme.brandPurple,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                ...dates.take(5).map((date) {
                  final dayLogs = grouped[date]!;
                  final label = _formatSessionDate(date);
                  return ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: Row(
                      children: [
                        Text(label,
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w600)),
                        const Spacer(),
                        Text(
                          '${dayLogs.length} log${dayLogs.length == 1 ? '' : 's'}',
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey.shade500),
                        ),
                      ],
                    ),
                    children: dayLogs
                        .map((log) => _buildLogRow(
                              context,
                              log,
                              prayerMap[log.prayerId] ?? 'Unknown Prayer',
                            ))
                        .toList(),
                  );
                }),
              ],
            );
          },
        ),
      ],
    );
  }

  String _todaySessionDate() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  String _formatSessionDate(String dateStr) {
    try {
      final parts = dateStr.split('-');
      final date = DateTime(
          int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
      final now = DateTime.now();
      final diff = now.difference(date).inDays;
      if (diff == 1) return 'Yesterday';
      if (diff < 7) {
        const days = [
          'Monday',
          'Tuesday',
          'Wednesday',
          'Thursday',
          'Friday',
          'Saturday',
          'Sunday'
        ];
        return days[date.weekday - 1];
      }
      const months = [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec'
      ];
      return '${months[date.month - 1]} ${date.day}';
    } catch (_) {
      return dateStr;
    }
  }

  Widget _buildGroupsSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const _PrayerSectionHeader(title: 'My Groups'),
            TextButton(
              onPressed: () => context.push(Routes.groups),
              child: const Text('View All'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _PremiumLinkTile(
          icon: Icons.groups_outlined,
          label: 'Pray together with your community',
          color: AppTheme.teal,
          onTap: () => context.push(Routes.groups),
        ),
      ],
    );
  }
}


// ─── Section Header ───────────────────────────────────────────────────────────

class _PrayerSectionHeader extends StatelessWidget {
  final String title;

  const _PrayerSectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 3,
          height: 18,
          decoration: BoxDecoration(
            color: AppTheme.brandBlue,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: AppTheme.textDark,
                fontWeight: FontWeight.w700,
              ),
        ),
      ],
    );
  }
}

// ─── Premium Link Tile ────────────────────────────────────────────────────────

class _PremiumLinkTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _PremiumLinkTile({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Material(
        color: color.withValues(alpha: 0.06),
        child: InkWell(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withValues(alpha: 0.18)),
            ),
            child: Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: color,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: color, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Empty State Card ─────────────────────────────────────────────────────────

class _EmptyStateCard extends StatelessWidget {
  final IconData icon;
  final String message;

  const _EmptyStateCard({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.grey.shade400),
          const SizedBox(width: 12),
          Text(
            message,
            style: TextStyle(color: Colors.grey.shade500, fontSize: 14),
          ),
        ],
      ),
    );
  }
}

// ─── Category Card ────────────────────────────────────────────────────────────

class _CategoryCard extends StatefulWidget {
  final String title;
  final int count;
  final Color color;
  final VoidCallback? onTap;

  const _CategoryCard({
    required this.title,
    required this.count,
    required this.color,
    this.onTap,
  });

  @override
  State<_CategoryCard> createState() => _CategoryCardState();
}

class _CategoryCardState extends State<_CategoryCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final lightBg = Color.lerp(widget.color, Colors.white, 0.78)!;

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap?.call();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.96 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: lightBg,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(alpha: 0.14),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Stack(
            children: [
              // Decorative circle
              Positioned(
                right: -14,
                bottom: -14,
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: widget.color.withValues(alpha: 0.10),
                  ),
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    widget.title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: widget.color.withValues(alpha: 0.75),
                      letterSpacing: 0.1,
                    ),
                  ),
                  Text(
                    widget.count.toString(),
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w700,
                      color: widget.color,
                      letterSpacing: -0.5,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
