import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/navigation/nav_config.dart';
import '../../core/theme/app_theme.dart';
import '../../core/tutorial/tutorial_providers.dart';
import 'connectivity_banner.dart';
import 'sync_degraded_banner.dart';

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

    // Visible position of the active branch; -1 (→ 0) if the current branch's
    // tab is hidden by config.
    var selectedIndex =
        tabs.indexWhere((t) => t.branchIndex == shell.currentIndex);
    if (selectedIndex < 0) selectedIndex = 0;

    return Scaffold(
      body: Column(
        children: [
          const ConnectivityBanner(),
          const SyncDegradedBanner(),
          Expanded(child: shell),
        ],
      ),
      bottomNavigationBar: _PremiumNavBar(
        key: tutorialKey(TutorialKeyId.bottomNavBar),
        tabs: tabs,
        selectedIndex: selectedIndex,
        onTap: (visibleIndex) {
          final branchIndex = tabs[visibleIndex].branchIndex;
          shell.goBranch(
            branchIndex,
            initialLocation: branchIndex == shell.currentIndex,
          );
        },
      ),
    );
  }
}

/// Premium M3 NavigationBar with a subtle top shadow separator.
/// Applies per-tab accent colors to the selected icon and label.
class _PremiumNavBar extends StatelessWidget {
  final List<NavTab> tabs;
  final int selectedIndex;
  final ValueChanged<int> onTap;

  const _PremiumNavBar({
    super.key,
    required this.tabs,
    required this.selectedIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final activeColor = tabs[selectedIndex].color;
    final baseTheme = Theme.of(context);

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
            indicatorColor: activeColor.withValues(alpha: AppTheme.alphaLightMed),
            iconTheme: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return IconThemeData(color: activeColor, size: AppTheme.iconLG);
              }
              return IconThemeData(color: AppTheme.unselectedColor, size: AppTheme.iconLG);
            }),
            labelTextStyle: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return AppTheme.tiny.copyWith(
                  fontWeight: FontWeight.w600,
                  color: activeColor,
                );
              }
              return AppTheme.tiny.copyWith(
                color: AppTheme.unselectedColor,
              );
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
              ),
          ],
          animationDuration: AppTheme.durationSlow,
        ),
      ),
    );
  }
}
