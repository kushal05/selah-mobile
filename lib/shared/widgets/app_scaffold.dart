import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/navigation/nav_config.dart';
import '../../core/theme/app_theme.dart';
import '../../core/tutorial/tutorial_providers.dart';
import 'connectivity_banner.dart';
import 'sync_degraded_banner.dart';
import '../../../core/providers/motion_preferences.dart';
import '../../core/theme/theme_colors.dart';
import '../../l10n/l10n.dart';

/// Main application scaffold with M3 NavigationBar.
/// Wraps the StatefulNavigationShell to provide tab-based navigation.
///
/// The router always registers all 7 branches; this scaffold only controls
/// which tabs are *shown* and in what order, driven by [navTabsProvider]
/// (remote-config overridable). Because the visible position can differ from
/// the router branch index, taps map back through each tab's [NavTab.branchIndex].
class AppScaffold extends ConsumerWidget {
  final StatefulNavigationShell shell;

  const AppScaffold({super.key, required this.shell});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tabs = ref.watch(navTabsProvider);

    // Split into the tabs that get their own slot and the rest, which live
    // behind "More". With <= kPrimaryNavTabCount + 1 visible tabs there is
    // nothing to overflow, so every tab keeps a slot and no More is shown.
    final needsMore = tabs.length > kPrimaryNavTabCount + 1;
    final primary = needsMore ? tabs.take(kPrimaryNavTabCount).toList() : tabs;
    final overflow = needsMore ? tabs.skip(kPrimaryNavTabCount).toList() : const <NavTab>[];

    // Position of the active branch among the primary tabs. If the active
    // branch lives in the overflow, More itself is the selected destination.
    var selectedIndex =
        primary.indexWhere((t) => t.branchIndex == shell.currentIndex);
    if (selectedIndex < 0) {
      selectedIndex = needsMore ? primary.length : 0;
    }

    void goToBranch(int branchIndex) {
      shell.goBranch(
        branchIndex,
        initialLocation: branchIndex == shell.currentIndex,
      );
    }

    return Scaffold(
      // The banners sit above the shell, so without this they render behind
      // the status bar and the offline notice is invisible on a notched
      // phone. SafeArea also removes the inset it consumes from the subtree's
      // MediaQuery, so the screens' own AppBars below do not pad for the
      // status bar a second time.
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const ConnectivityBanner(),
            const SyncDegradedBanner(),
            Expanded(child: shell),
          ],
        ),
      ),
      bottomNavigationBar: _PremiumNavBar(
        key: tutorialKey(TutorialKeyId.bottomNavBar),
        tabs: primary,
        overflow: overflow,
        selectedIndex: selectedIndex,
        onTap: (visibleIndex) {
          if (visibleIndex < primary.length) {
            goToBranch(primary[visibleIndex].branchIndex);
            return;
          }
          _showMoreSheet(
            context,
            overflow: overflow,
            currentBranchIndex: shell.currentIndex,
            onSelect: goToBranch,
          );
        },
      ),
    );
  }
}

/// Bottom sheet listing the destinations that did not fit in the bar.
///
/// Rows are full-width and 56px tall — deliberately larger than a bar tab,
/// since this sheet is the fallback for anyone who found the bar's targets
/// hard to hit in the first place.
void _showMoreSheet(
  BuildContext context, {
  required List<NavTab> overflow,
  required int currentBranchIndex,
  required ValueChanged<int> onSelect,
}) {
  showModalBottomSheet<void>(
      // Defaults to false: a scroll-controlled sheet otherwise draws its
      // top edge behind the notch or Dynamic Island.
      useSafeArea: true,
    context: context,
    backgroundColor: context.cardSurface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 12),
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: context.subtleFill,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(20, 20, 20, 8),
            child: Text(
              l10n(context).navMore,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
          for (final tab in overflow)
            _MoreRow(
              tab: tab,
              selected: tab.branchIndex == currentBranchIndex,
              onTap: () {
                Navigator.of(sheetContext).pop();
                onSelect(tab.branchIndex);
              },
            ),
          const SizedBox(height: 12),
        ],
      ),
    ),
  );
}

class _MoreRow extends StatelessWidget {
  final NavTab tab;
  final bool selected;
  final VoidCallback onTap;

  const _MoreRow({
    required this.tab,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accent = AppTheme.accentOnLight(tab.color);
    return Semantics(
      button: true,
      selected: selected,
      label: tab.label,
      excludeSemantics: true,
      // onTap must live on this node: excludeSemantics drops the child's
      // tap action, so without it the control announces as a button but
      // cannot be activated — the exact bug the onTapUp fix removed.
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          color: selected ? accent.withValues(alpha: 0.08) : null,
          child: Row(
            children: [
              Icon(selected ? tab.selectedIcon : tab.icon,
                  size: AppTheme.iconXL, color: accent),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  tab.label,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
              if (selected)
                Icon(Icons.check_rounded, size: AppTheme.iconBase, color: accent),
            ],
          ),
        ),
      ),
    );
  }
}

/// Premium M3 NavigationBar with a subtle top shadow separator.
/// Applies per-tab accent colors to the selected icon and label.
class _PremiumNavBar extends StatelessWidget {
  final List<NavTab> tabs;
  final List<NavTab> overflow;
  final int selectedIndex;
  final ValueChanged<int> onTap;

  const _PremiumNavBar({
    super.key,
    required this.tabs,
    required this.overflow,
    required this.selectedIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // selectedIndex may point at the More slot, which sits past `tabs`.
    // accentOnLight unconditionally meant the selected tab wore the light
    // theme's accent variant in dark mode. Both values are audited tokens, so
    // the contrast check could not see it — it was the wrong half of a
    // correct pair.
    final activeColor = AppTheme.accentOnTintFor(
      selectedIndex < tabs.length
          ? tabs[selectedIndex].color
          : AppTheme.brandBlue,
      Theme.of(context).brightness,
    );
    final baseTheme = Theme.of(context);
    // This rebuilds navigationBarTheme, so it must carry the theme's own
    // unselected colour forward — hardcoding the light grey here silently
    // overrode the dark theme's nav colours.
    final unselected = baseTheme.colorScheme.onSurfaceVariant;

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: Colors.black.withValues(alpha: AppTheme.alphaSubtle),
            width: 0.5,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: AppTheme.spacing12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Theme(
        data: baseTheme.copyWith(
          navigationBarTheme: baseTheme.navigationBarTheme.copyWith(
            indicatorColor: activeColor.withValues(alpha: AppTheme.alphaMedium),
            iconTheme: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return IconThemeData(color: activeColor, size: AppTheme.iconLG);
              }
              return IconThemeData(color: unselected, size: AppTheme.iconLG);
            }),
            labelTextStyle: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return AppTheme.tiny.copyWith(
                  fontWeight: FontWeight.w600,
                  color: activeColor,
                );
              }
              return AppTheme.tiny.copyWith(color: unselected);
            }),
          ),
        ),
        child: NavigationBar(
          selectedIndex: selectedIndex,
          onDestinationSelected: onTap,
          destinations: [
            for (final tab in tabs)
              NavigationDestination(
                icon: Icon(tab.icon),
                selectedIcon: Icon(tab.selectedIcon),
                label: tab.label,
                tooltip: tab.label,
              ),
            if (overflow.isNotEmpty)
              NavigationDestination(
                icon: Icon(Icons.more_horiz_rounded),
                selectedIcon: Icon(Icons.more_horiz_rounded),
                label: l10n(context).navMore,
                tooltip: l10n(context).moreSections,
              ),
          ],
          animationDuration: context.motion(AppTheme.durationSlow),
        ),
      ),
    );
  }
}
