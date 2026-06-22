import 'remote_config_keys.dart';

/// The in-code source of truth for every remote-config key.
///
/// The effective config is ALWAYS these defaults overlaid with whatever the
/// server returned, key by key. A key the server omits keeps its default here;
/// an empty/failed/offline server response means the effective config IS this
/// map. This makes it structurally impossible for a bad server payload to drop
/// a key the app depends on.
///
/// Values must be JSON-serialisable Dart (bool / int / String / List / Map) so
/// the same shapes can arrive from the server as overrides:
///  - scalar keys (flags, limits, copy) hold their literal default value.
///  - "catalog" keys (nav, settings, home) hold an empty override MAP `{}`:
///    the real catalog (icons, onTap, default labels) lives in code, and the
///    server only overrides per-id `visible` / `order` / `label`.
///  - pure-content keys (suggested prayers, onboarding, tab colours) hold the
///    full default list, since the server replaces them wholesale.
class RemoteConfigDefaults {
  RemoteConfigDefaults._();

  static const Map<String, Object> values = {
    // ── Kill switches ────────────────────────────────────────────────────
    RcKeys.maintenanceMode: false,

    // ── Feature flags (all on by default) ────────────────────────────────
    RcKeys.featureNotes: true,
    RcKeys.featurePrayers: true,
    RcKeys.featureBible: true,
    RcKeys.featurePromises: true,
    RcKeys.featureSongs: true,
    RcKeys.featureSocial: true,

    // ── Tunable limits / timings (mirror the current hardcoded values) ────
    RcKeys.syncDebounceMs: 500,
    RcKeys.editorBatchMs: 400,
    RcKeys.httpTimeoutSec: 12,
    RcKeys.syncHttpTimeoutSec: 30,
    RcKeys.syncMaxBatchSize: 100,
    RcKeys.syncPullBatchSize: 100,
    RcKeys.periodicSyncIntervalMin: 15,
    RcKeys.syncMaxRetries: 3,
    RcKeys.updateCheckIntervalMin: 60,
    RcKeys.prayerReminderHour: 8,
    RcKeys.prayerReminderMinute: 0,
    RcKeys.recentNotesLimit: 10,

    // ── Remote content ───────────────────────────────────────────────────
    RcKeys.suggestedPrayers: _suggestedPrayers,
    RcKeys.onboardingPages: _onboardingPages,
    RcKeys.aboutDescription:
        'Your spiritual companion for notes, prayers, promises, and songs — all in one place.',

    // ── Structure / catalog overrides (empty = no override) ──────────────
    RcKeys.navTabs: <String, Object>{},
    RcKeys.homeSections: <String, Object>{},
    RcKeys.settingsSections: <String, Object>{},
  };

  // Current 6 suggested-prayer templates (shown when the user has 0 active).
  static const List<Map<String, String>> _suggestedPrayers = [
    {
      'title': 'Daily Gratitude',
      'description':
          'Thank God for His blessings today — health, family, provision, and grace.',
    },
    {
      'title': 'Wisdom & Guidance',
      'description':
          'Ask the Lord for wisdom in decisions, direction for the day, and clarity of purpose.',
    },
    {
      'title': 'Family & Loved Ones',
      'description':
          'Pray for the protection, health, and spiritual growth of your family members.',
    },
    {
      'title': 'Strength in Trials',
      'description':
          'Ask God for endurance and peace during difficult seasons and challenges.',
    },
    {
      'title': 'Church & Community',
      'description':
          'Lift up your church leaders, fellowship groups, and the unity of believers.',
    },
    {
      'title': 'The Lost & Unreached',
      'description':
          "Pray for those who don't yet know Christ — for open hearts and divine encounters.",
    },
  ];

  // Current 4 onboarding pages. `icon`/`orbitIcons` are icon-registry names;
  // `color` is #RRGGBB; `useAppIcon` renders the app PNG instead of `icon`.
  static const List<Map<String, Object>> _onboardingPages = [
    {
      'icon': 'auto_awesome',
      'title': 'Welcome to Selah',
      'subtitle': 'Pause. Reflect. Grow.',
      'color': '#7B61FF',
      'orbitIcons': ['spa', 'light_mode'],
      'useAppIcon': true,
    },
    {
      'icon': 'menu_book',
      'title': 'Capture what God\nteaches you',
      'subtitle':
          'Take sermon notes, highlight scripture, and organize your spiritual insights in one beautiful place.',
      'color': '#2D6CDF',
      'orbitIcons': ['edit_note', 'bookmark_add'],
      'useAppIcon': false,
    },
    {
      'icon': 'favorite',
      'title': 'Keep track of\nyour prayers',
      'subtitle':
          "Record prayer requests, track answers, and build a journal of God's faithfulness over time.",
      'color': '#4C8EF7',
      'orbitIcons': ['bookmark', 'star_outline'],
      'useAppIcon': false,
    },
    {
      'icon': 'people',
      'title': 'Grow together',
      'subtitle':
          'Share prayer requests with friends, join groups, and encourage one another in your faith journey.',
      'color': '#8F9CFF',
      'orbitIcons': ['church', 'handshake'],
      'useAppIcon': false,
    },
  ];

}
