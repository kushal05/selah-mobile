import 'package:shared_preferences/shared_preferences.dart';

/// Manages the tutorial's pending / seen flags in SharedPreferences.
///
/// Keys:
///   `pending_tutorial`  — true when the tutorial should run on next home load.
///   `has_seen_tutorial` — true once the user has completed or skipped the tutorial.
class TutorialService {
  final SharedPreferences _prefs;

  TutorialService(this._prefs);

  static const _pendingKey = 'pending_tutorial';
  static const _seenKey = 'has_seen_tutorial';

  /// Returns true when the tutorial has been queued but not yet run.
  bool isPending() => _prefs.getBool(_pendingKey) ?? false;

  /// Queues the tutorial to run on the next home screen load.
  /// Called after a fresh registration.
  Future<void> setPending() => _prefs.setBool(_pendingKey, true);

  /// Marks the tutorial as completed and clears the pending flag.
  Future<void> markSeen() => Future.wait([
        _prefs.setBool(_pendingKey, false),
        _prefs.setBool(_seenKey, true),
      ]);

  /// Resets both flags so the tutorial will run again on the next home load.
  /// Used by the "Replay Tutorial" option in Settings.
  Future<void> resetForReplay() async {
    await _prefs.setBool(_pendingKey, true);
    await _prefs.remove(_seenKey);
  }
}
