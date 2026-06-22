/// Canonical namespaced keys for remote config. Using constants (instead of
/// raw strings at call sites) prevents typos and gives one place to audit what
/// the backend can override.
///
/// EVERY key here MUST have a default in [RemoteConfigDefaults.values] — a unit
/// test enforces this so a typo can never silently read a missing key.
class RcKeys {
  RcKeys._();

  // ── App-level kill switches ──────────────────────────────────────────────
  static const maintenanceMode = 'app.maintenanceMode';

  // ── Feature flags (gate whole features / nav entries) ────────────────────
  static const featureNotes = 'feature.notes.enabled';
  static const featurePrayers = 'feature.prayers.enabled';
  static const featureBible = 'feature.bible.enabled';
  static const featurePromises = 'feature.promises.enabled';
  static const featureSongs = 'feature.songs.enabled';
  static const featureSocial = 'feature.social.enabled';

  // ── Tunable numeric limits / timings ─────────────────────────────────────
  static const syncDebounceMs = 'limits.syncDebounceMs';
  static const editorBatchMs = 'limits.editorBatchMs';
  static const httpTimeoutSec = 'limits.httpTimeoutSec';
  static const syncHttpTimeoutSec = 'limits.syncHttpTimeoutSec';
  static const syncMaxBatchSize = 'limits.syncMaxBatchSize';
  static const syncPullBatchSize = 'limits.syncPullBatchSize';
  static const periodicSyncIntervalMin = 'limits.periodicSyncIntervalMin';
  static const syncMaxRetries = 'limits.syncMaxRetries';
  static const updateCheckIntervalMin = 'limits.updateCheckIntervalMin';
  static const prayerReminderHour = 'limits.prayerReminderHour';
  static const prayerReminderMinute = 'limits.prayerReminderMinute';
  static const recentNotesLimit = 'limits.recentNotesLimit';

  // ── Remote content ───────────────────────────────────────────────────────
  static const suggestedPrayers = 'content.suggestedPrayers';
  static const onboardingPages = 'content.onboardingPages';
  static const aboutDescription = 'content.aboutDescription';

  // ── Navigation / structure (Tier 2) ──────────────────────────────────────
  // Override MAPS keyed by stable id → {visible, order, label, icon, color}.
  // The catalog (icons, onTap, default copy) stays in code; config only tweaks
  // presentation. Item-level home/settings overrides can be layered on later
  // using the same pattern.
  static const navTabs = 'nav.tabs';
  static const homeSections = 'home.sections';
  static const settingsSections = 'settings.sections';

  /// Every key the app reads. The defaults-coverage test iterates this.
  static const List<String> all = [
    maintenanceMode,
    featureNotes,
    featurePrayers,
    featureBible,
    featurePromises,
    featureSongs,
    featureSocial,
    syncDebounceMs,
    editorBatchMs,
    httpTimeoutSec,
    syncHttpTimeoutSec,
    syncMaxBatchSize,
    syncPullBatchSize,
    periodicSyncIntervalMin,
    syncMaxRetries,
    updateCheckIntervalMin,
    prayerReminderHour,
    prayerReminderMinute,
    recentNotesLimit,
    suggestedPrayers,
    onboardingPages,
    aboutDescription,
    navTabs,
    homeSections,
    settingsSections,
  ];
}
