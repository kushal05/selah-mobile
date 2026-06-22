import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../sync/providers/sync_providers.dart';
import 'tutorial_service.dart';
import 'tutorial_state.dart';

final tutorialServiceProvider = Provider<TutorialService>(
  (ref) => TutorialService(ref.watch(sharedPreferencesProvider)),
);

final tutorialStateProvider = StateProvider<TutorialState>(
  (ref) => const TutorialState.inactive(),
);

/// Set to true by Settings when the user taps "Replay App Tour".
/// Home screen listens to this and starts the tour immediately, even when the
/// widget is already alive inside a StatefulShellBranch (initState won't re-run).
final tutorialReplayRequestedProvider = StateProvider<bool>((ref) => false);

// ─── GlobalKey registry ───────────────────────────────────────────────────────

/// All UI targets that can be spotlighted during the tutorial.
enum TutorialKeyId {
  bottomNavBar,
  quickActionsRow,
  dailyFocusCard,
}

final Map<TutorialKeyId, GlobalKey> _keyRegistry = {};

/// Returns (or creates) the [GlobalKey] for a given tutorial target.
///
/// Call this at the widget's build site to attach the key:
/// ```dart
/// QuickActionsRow(key: tutorialKey(TutorialKeyId.quickActionsRow))
/// ```
GlobalKey tutorialKey(TutorialKeyId id) {
  return _keyRegistry.putIfAbsent(
    id,
    () => GlobalKey(debugLabel: 'tutorial_${id.name}'),
  );
}
