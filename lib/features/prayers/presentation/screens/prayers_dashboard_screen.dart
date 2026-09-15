import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/domain/enums/prayer_enums.dart';
import '../../../../core/navigation/routes.dart';
import '../../../../core/sync/models/prayer_model.dart';
import '../../../../core/sync/providers/sync_providers.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/skeletons/skeletons.dart';
import '../../../../core/services/user_facing_error.dart';
import '../../../../shared/widgets/feature_intro.dart';
import '../../../../core/theme/theme_colors.dart';
import '../../../../l10n/l10n.dart';
import '../widgets/quick_prayer_sheet.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../../../shared/widgets/cards/prayer_card.dart';
import '../../../../shared/widgets/row_actions.dart';
import '../../../../shared/widgets/undo_snackbar.dart';
import '../../domain/models/prayer_metadata_codec.dart';
import '../../../../core/navigation/tab_navigation.dart';
import '../../../../shared/widgets/filter_pill.dart';
import '../../../../shared/widgets/tab_title.dart';

/// Prayers dashboard screen with real data from local database
/// Which slice of the list is showing.
///
/// Active / Answered / All were four tiles in a grid, which made them look
/// like four destinations. They are three views of one list, so they are a
/// filter — and the list stays on screen while you switch.
enum _PrayerFilter {
  active,
  answered,
  all;

  List<PrayerModel> apply(List<PrayerModel> prayers) => switch (this) {
        _PrayerFilter.active => prayers
            .where((p) => p.status == PrayerStatus.active)
            .toList(),
        _PrayerFilter.answered => prayers
            .where((p) => p.status == PrayerStatus.answered)
            .toList(),
        _PrayerFilter.all => prayers,
      };

  String label(BuildContext context) => switch (this) {
        _PrayerFilter.active => l10n(context).active,
        _PrayerFilter.answered => l10n(context).answered,
        _PrayerFilter.all => l10n(context).all,
      };

  String emptyTitle(BuildContext context) => switch (this) {
        _PrayerFilter.active => l10n(context).noActivePrayers,
        _PrayerFilter.answered => l10n(context).noAnsweredPrayersYet,
        _PrayerFilter.all => l10n(context).noPrayersYet,
      };

  String emptyMessage(BuildContext context) => switch (this) {
        _PrayerFilter.active =>
          l10n(context).addAPrayerAndItWillAppearHere,
        _PrayerFilter.answered =>
          l10n(context).markAPrayerAnsweredToSeeItHere,
        _PrayerFilter.all => l10n(context).addAPrayerAndItWillAppearHere,
      };
}

/// Held outside the widget so the chosen slice survives navigating into a
/// prayer and back — losing it on every return made the filter feel broken.
final _prayerFilterProvider =
    StateProvider<_PrayerFilter>((ref) => _PrayerFilter.active);

class PrayersDashboardScreen extends ConsumerWidget {
  const PrayersDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(_prayerFilterProvider);
    final prayersAsync = ref.watch(prayersStreamProvider);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && context.mounted) {
          goToTab(context, 0); // Switch to Home tab
        }
      },
      child: Scaffold(
        backgroundColor: context.pageGround,
        appBar: AppBar(
          backgroundColor: context.pageGround,
          elevation: 0,
          automaticallyImplyLeading: false,
          title: TabTitle(l10n(context).navPrayers),
          actions: [
            IconButton(
              icon: const Icon(Icons.search_rounded),
              tooltip: l10n(context).actionSearch,
              onPressed: () => context.push(Routes.search),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton(
          heroTag: null,
          backgroundColor: AppTheme.brandBlue,
          foregroundColor: AppTheme.onAccent(AppTheme.brandBlue),
          onPressed: () => showQuickPrayerSheet(context),
          child: const Icon(Icons.add_rounded),
        ),
        body: prayersAsync.when(
          loading: () => const DashboardSkeleton(),
          error: (error, stack) => Center(child: Text(UserFacingError.forLoad(error))),
          data: (prayers) {
            final visible = filter.apply(prayers);
            return CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      FeatureIntros.prayers,
                      _buildPrayTodayBanner(context, ref),
                      // One rhythm between blocks. Two stacked spacers left
                      // from an earlier edit put 28 here and 16 below it.
                      const SizedBox(height: AppTheme.spacing16),
                      _buildShortcuts(context),
                      const SizedBox(height: AppTheme.spacing16),
                      _buildFilterBar(context, ref, prayers, filter),
                      const SizedBox(height: AppTheme.spacing12),
                    ]),
                  ),
                ),
                if (visible.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: EmptyState(
                      icon: Icons.favorite_outline_rounded,
                      title: filter.emptyTitle(context),
                      message: filter.emptyMessage(context),
                      // No action button: the + below does exactly this, and
                      // two controls for one action read as two actions. The
                      // message points at the one that is always there.
                      actionLabel: null,
                      onAction: null,
                      accent: AppTheme.brandBlue,
                    ),
                  )
                else
                  SliverPadding(
                    // No horizontal inset: PrayerCard carries cardMargin
                    // itself. Adding 16 here made every row 32 from the edge
                    // while the banner above sat at 16.
                    padding: const EdgeInsets.fromLTRB(0, 0, 0, 96),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, i) => _buildPrayerRow(context, ref, visible[i]),
                        childCount: visible.length,
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }



  /// Active / Answered / All, with counts, as one row that keeps the list on
  /// screen. Replaces the four-tile grid, which pushed the prayers themselves
  /// below the fold on every visit.

  /// Insights, Updates and Groups, on the screen rather than behind ⋮.
  ///
  /// A new user does not open an overflow menu to discover what a tab can do,
  /// so anything only reachable from one is effectively unshipped. These three
  /// are secondary to the list — hence a compact row rather than the
  /// full-width sections they used to be — but they are visible.
  ///
  /// People is not here: it is a directory that happens to be referenced by
  /// prayers, not a prayer surface, and it has its own tab.
  Widget _buildShortcuts(BuildContext context) {
    final items = [
      (
        Icons.insights_rounded,
        l10n(context).insights,
        AppTheme.brandPurple,
        Routes.prayerAnalytics
      ),
      (
        Icons.campaign_outlined,
        l10n(context).updates,
        AppTheme.orange,
        Routes.prayerUpdatesFeed
      ),
      (
        Icons.groups_outlined,
        l10n(context).myGroups,
        AppTheme.teal,
        Routes.groups
      ),
    ];
    return Row(
      children: [
        for (final (icon, label, accent, route) in items) ...[
          Expanded(
            child: _ShortcutTile(
              icon: icon,
              label: label,
              accent: accent,
              onTap: () => context.push(route),
            ),
          ),
          if (route != items.last.$4) const SizedBox(width: AppTheme.spacing10),
        ],
      ],
    );
  }

  Widget _buildFilterBar(BuildContext context, WidgetRef ref,
      List<PrayerModel> prayers, _PrayerFilter selected) {
    // Equal thirds rather than a scrolling row of content-sized chips. There
    // are exactly three, they always fit, and ragged widths beside the
    // even shortcut tiles below read as a mistake.
    return Row(
      children: [
        for (final f in _PrayerFilter.values) ...[
          Expanded(
            child: FilterPill(
              label: f.label(context),
              count: f.apply(prayers).length,
              selected: f == selected,
              onTap: () => ref.read(_prayerFilterProvider.notifier).state = f,
              accent: AppTheme.brandBlue,),
          ),
          if (f != _PrayerFilter.values.last)
            const SizedBox(width: AppTheme.spacing10),
        ],
      ],
    );
  }

  Widget _buildPrayerRow(
      BuildContext context, WidgetRef ref, PrayerModel prayer) {
    final metadata = decodePrayerMetadata(prayer.category ?? '');
    final peopleNames = ref
            .watch(peopleStreamProvider)
            .valueOrNull
            ?.where((p) => metadata.linkedPeopleIds.contains(p.id))
            .map((p) => p.name)
            .toList() ??
        const <String>[];

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: PrayerCard(
        title: prayer.title,
        frequencyLabel: prayer.frequency.displayName,
        statusLabel: prayer.status.displayName,
        statusColor: _statusColor(prayer.status),
        description: prayer.content,
        linkedPeopleNames: peopleNames,
        showStatusBadge: prayer.status != PrayerStatus.active,
        onTap: () => context.push('/prayers/${prayer.id}'),
        actions: [
          RowAction(
            icon: Icons.delete_outline_rounded,
            label: l10n(context).moveToTrash,
            isDestructive: true,
            onSelected: () async {
              final confirmed = await _confirmTrash(context);
              if (!confirmed || !context.mounted) return;
              final repo = ref.read(prayerRepositoryProvider);
              try {
                await repo.trashPrayer(prayer.id);
                if (!context.mounted) return;
                showUndoSnackBar(
                  context,
                  itemLabel: l10n(context).prayer,
                  onUndo: () => repo.restorePrayer(prayer.id),
                );
              } catch (e) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(
                      UserFacingError.message(e, action: 'move this prayer to Trash')),
                  behavior: SnackBarBehavior.floating,
                  backgroundColor: AppTheme.errorSurface,
                ));
              }
            },
          ),
        ],
      ),
    );
  }

  Color _statusColor(PrayerStatus status) => switch (status) {
        PrayerStatus.active => AppTheme.brandBlue,
        PrayerStatus.answered => AppTheme.emerald,
        PrayerStatus.archived => AppTheme.mutedGrey,
      };

  Future<bool> _confirmTrash(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n(context).moveToTrash),
        content: Text(l10n(context).thisPrayerCanBeRestoredFromTrash),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n(context).actionCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n(context).moveToTrash),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Widget _buildPrayTodayBanner(BuildContext context, WidgetRef ref) {
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
                        Text(
                          l10n(context).prayToday,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.2,
                          ),
                        ),
                        // The streak was a full card of its own, competing
                        // with the session it exists to motivate. It reads
                        // better as one line on the thing you are about to do.
                        Builder(builder: (context) {
                          final streak =
                              ref.watch(prayerStreakProvider).valueOrNull ?? 0;
                          return Text(
                            streak > 0
                                ? l10n(context).nDayStreak(streak)
                                : l10n(context).startYourDailyPrayerSession,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.85),
                              fontSize: 14,
                            ),
                          );
                        }),
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







}





// ─── Category Card ────────────────────────────────────────────────────────────




/// One secondary destination from the Prayers tab.
class _ShortcutTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color accent;
  final VoidCallback onTap;

  const _ShortcutTile({
    required this.icon,
    required this.label,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final glyph = AppTheme.accentOnTintFor(accent, brightness);
    return Semantics(
      button: true,
      child: Material(
        color: glyph.withValues(alpha: AppTheme.alphaLight),
        borderRadius: AppTheme.borderRadius2XL,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppTheme.borderRadius2XL,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: AppTheme.iconBase, color: glyph),
                const SizedBox(height: 6),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    // Hued ink, not white: these tiles are a pale tint, and
                    // white on them is unreadable in light mode.
                    color: AppTheme.inkOnTintFor(accent, brightness),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}


