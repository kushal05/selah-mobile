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
    for (final id in _featureIntroKeys) {
      await _prefs.remove(id);
    }
  }

  // ── Per-feature first-use intros ────────────────────────────────────────
  // The home tour covered one screen out of seven. Notes, Bible, Prayers,
  // Promises, Songs and Social were entered cold, with no explanation of what
  // the tab is for — the single biggest gap for someone who does not already
  // know the app.
  //
  // Each tab shows a one-time introduction the first time it is opened. These
  // are separate from the home tour so a user who skipped that still gets
  // told what each section does.

  static const _featureIntroPrefix = 'feature_intro_seen_';
  static const _featureIntroKeys = <String>[
    '${_featureIntroPrefix}notes',
    '${_featureIntroPrefix}bible',
    '${_featureIntroPrefix}prayers',
    '${_featureIntroPrefix}promises',
    '${_featureIntroPrefix}songs',
    '${_featureIntroPrefix}social',
  ];

  /// Whether [featureId]'s introduction still needs to be shown.
  bool needsFeatureIntro(String featureId) =>
      !(_prefs.getBool('$_featureIntroPrefix$featureId') ?? false);

  /// Records that [featureId]'s introduction has been seen.
  Future<void> markFeatureIntroSeen(String featureId) =>
      _prefs.setBool('$_featureIntroPrefix$featureId', true);
}
