import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../sync/providers/sync_providers.dart';

/// The user's light / dark preference. Persists across launches.
///
/// Defaults to [ThemeMode.system], so someone who has already set their phone
/// to dark gets a dark app without discovering this setting at all — which is
/// most of the people who need it.
final themeModeProvider =
    NotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);

class ThemeModeNotifier extends Notifier<ThemeMode> {
  static const _prefsKey = 'theme_mode';

  SharedPreferences get _prefs => ref.read(sharedPreferencesProvider);

  @override
  ThemeMode build() {
    final stored = _prefs.getString(_prefsKey);
    return switch (stored) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  Future<void> set(ThemeMode mode) async {
    if (mode == state) return;
    state = mode;
    await _prefs.setString(_prefsKey, mode.name);
  }
}

/// Human-facing label for a [ThemeMode], for the settings control.
extension ThemeModeLabel on ThemeMode {
  String get label => switch (this) {
        ThemeMode.light => 'Light',
        ThemeMode.dark => 'Dark',
        ThemeMode.system => 'Match device',
      };

  String get description => switch (this) {
        ThemeMode.light => 'Always use the light theme',
        ThemeMode.dark => 'Always use the dark theme',
        ThemeMode.system => 'Follow your phone’s setting',
      };

  IconData get icon => switch (this) {
        ThemeMode.light => Icons.light_mode_outlined,
        ThemeMode.dark => Icons.dark_mode_outlined,
        ThemeMode.system => Icons.brightness_auto_outlined,
      };
}
