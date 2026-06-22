import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/remote/icon_registry.dart';
import '../config/remote/remote_config_keys.dart';
import '../config/remote/remote_config_providers.dart';
import '../theme/app_theme.dart';

/// One bottom-navigation tab.
///
/// [branchIndex] is the FIXED `StatefulShellRoute` branch this tab drives. It is
/// structural — the router always registers all 7 branches, and the server can
/// never change the branch wiring or the set of tab ids. The server MAY override
/// a tab's presentation: `visible`, `label`, `icon`, `color`, and `order`.
class NavTab {
  final String id;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final int branchIndex;
  final Color color;

  const NavTab({
    required this.id,
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.branchIndex,
    required this.color,
  });

  NavTab _override({
    String? label,
    IconData? icon,
    IconData? selectedIcon,
    Color? color,
  }) {
    return NavTab(
      id: id,
      label: label ?? this.label,
      icon: icon ?? this.icon,
      selectedIcon: selectedIcon ?? this.selectedIcon,
      branchIndex: branchIndex,
      color: color ?? this.color,
    );
  }
}

/// The 7 base tabs, in router-branch order. This is the in-code default the
/// server overlays — and the guaranteed fallback if a bad override would hide
/// everything.
const List<NavTab> kDefaultNavTabs = [
  NavTab(
    id: 'home',
    label: 'Home',
    icon: Icons.home_outlined,
    selectedIcon: Icons.home_rounded,
    branchIndex: 0,
    color: AppTheme.brandBlue,
  ),
  NavTab(
    id: 'notes',
    label: 'Notes',
    icon: Icons.description_outlined,
    selectedIcon: Icons.description_rounded,
    branchIndex: 1,
    color: AppTheme.brandPurple,
  ),
  NavTab(
    id: 'prayers',
    label: 'Prayers',
    icon: Icons.favorite_outline_rounded,
    selectedIcon: Icons.favorite_rounded,
    branchIndex: 2,
    color: AppTheme.brandBlue,
  ),
  NavTab(
    id: 'bible',
    label: 'Bible',
    icon: Icons.menu_book_outlined,
    selectedIcon: Icons.menu_book_rounded,
    branchIndex: 3,
    color: AppTheme.emerald,
  ),
  NavTab(
    id: 'promises',
    label: 'Promises',
    icon: Icons.bookmark_outline_rounded,
    selectedIcon: Icons.bookmark_rounded,
    branchIndex: 4,
    color: AppTheme.rosePink,
  ),
  NavTab(
    id: 'songs',
    label: 'Songs',
    icon: Icons.music_note_outlined,
    selectedIcon: Icons.music_note_rounded,
    branchIndex: 5,
    color: AppTheme.orange,
  ),
  NavTab(
    id: 'social',
    label: 'Social',
    icon: Icons.groups_outlined,
    selectedIcon: Icons.groups_rounded,
    branchIndex: 6,
    color: AppTheme.teal,
  ),
];

/// The effective, ordered, visible bottom-nav tabs: the base tabs overlaid with
/// per-id remote overrides (visible / label / icon / color / order).
///
/// Guardrail: if the override would hide every tab or drop Home, the override is
/// ignored and the full default set is returned — the app can never be left
/// without navigation.
/// Maps a tab id to its feature-flag key. A tab whose flag is false is hidden
/// (a clean kill switch, independent of the nav presentation overrides). Home
/// has no flag — it is always available.
const Map<String, String> _tabFeatureFlag = {
  'notes': RcKeys.featureNotes,
  'prayers': RcKeys.featurePrayers,
  'bible': RcKeys.featureBible,
  'promises': RcKeys.featurePromises,
  'songs': RcKeys.featureSongs,
  'social': RcKeys.featureSocial,
};

final navTabsProvider = Provider<List<NavTab>>((ref) {
  final rc = ref.watch(remoteConfigProvider);
  final overrides = rc.getJson(RcKeys.navTabs);

  // (order, baseIndex, tab) — baseIndex breaks ties so duplicate/equal `order`
  // values stay deterministic regardless of Dart's (unstable) List.sort.
  final positioned = <(int, int, NavTab)>[];
  for (var i = 0; i < kDefaultNavTabs.length; i++) {
    final base = kDefaultNavTabs[i];

    // Feature kill switch: a disabled feature hides its tab entirely.
    final flag = _tabFeatureFlag[base.id];
    if (flag != null && !rc.getBool(flag, fallback: true)) continue;

    final ov = overrides[base.id];
    var order = i;
    var tab = base;

    if (ov is Map) {
      if (ov['visible'] == false) continue; // hidden
      if (ov['order'] is num) order = (ov['order'] as num).toInt();
      final iconName = ov['icon']?.toString();
      final overrideIcon = iconName == null ? null : iconFor(iconName);
      tab = base._override(
        label: ov['label']?.toString(),
        icon: overrideIcon,
        selectedIcon: overrideIcon,
        color: colorFromHex(ov['color']?.toString()),
      );
    }
    positioned.add((order, i, tab));
  }

  positioned.sort((a, b) {
    final c = a.$1.compareTo(b.$1);
    return c != 0 ? c : a.$2.compareTo(b.$2);
  });
  final result = positioned.map((e) => e.$3).toList();

  if (result.isEmpty || !result.any((t) => t.id == 'home')) {
    return kDefaultNavTabs;
  }
  return result;
});
