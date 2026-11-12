import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/sync/providers/sync_providers.dart';
import '../../../../core/theme/app_theme.dart';

/// The face the chapter text is set in.
enum ReaderTypeface {
  serif,
  sans;

  /// Fonts to try, in order. Only system fonts: a serif face is not bundled, so
  /// each platform uses its own (Noto Serif on Android, Georgia elsewhere).
  String? get family => this == serif ? 'Georgia' : null;
  List<String> get fallback =>
      this == serif ? const ['Noto Serif', 'serif'] : const [];
}

/// Space between lines of the chapter text, as a line-height multiple.
enum ReaderLineSpacing {
  compact(1.5),
  normal(1.72),
  roomy(1.95);

  const ReaderLineSpacing(this.height);
  final double height;
}

T _read<T extends Enum>(SharedPreferences prefs, String key, List<T> values,
    T fallback) {
  final stored = prefs.getString(key);
  // A value from a newer build must not brick the reader.
  return values.where((v) => v.name == stored).firstOrNull ?? fallback;
}

final readerTypefaceProvider =
    NotifierProvider<ReaderTypefaceNotifier, ReaderTypeface>(
        ReaderTypefaceNotifier.new);

class ReaderTypefaceNotifier extends Notifier<ReaderTypeface> {
  static const _key = 'bible_reader_typeface';

  @override
  ReaderTypeface build() => _read(ref.read(sharedPreferencesProvider), _key,
      ReaderTypeface.values, ReaderTypeface.serif);

  Future<void> set(ReaderTypeface v) async {
    if (v == state) return;
    state = v;
    await ref.read(sharedPreferencesProvider).setString(_key, v.name);
  }
}

final readerLineSpacingProvider =
    NotifierProvider<ReaderLineSpacingNotifier, ReaderLineSpacing>(
        ReaderLineSpacingNotifier.new);

class ReaderLineSpacingNotifier extends Notifier<ReaderLineSpacing> {
  static const _key = 'bible_reader_line_spacing';

  @override
  ReaderLineSpacing build() => _read(ref.read(sharedPreferencesProvider), _key,
      ReaderLineSpacing.values, ReaderLineSpacing.normal);

  Future<void> set(ReaderLineSpacing v) async {
    if (v == state) return;
    state = v;
    await ref.read(sharedPreferencesProvider).setString(_key, v.name);
  }
}

final readerShowVerseNumbersProvider =
    NotifierProvider<ReaderShowVerseNumbersNotifier, bool>(
        ReaderShowVerseNumbersNotifier.new);

class ReaderShowVerseNumbersNotifier extends Notifier<bool> {
  static const _key = 'bible_reader_show_verse_numbers';

  @override
  bool build() => ref.read(sharedPreferencesProvider).getBool(_key) ?? true;

  Future<void> set(bool v) async {
    if (v == state) return;
    state = v;
    await ref.read(sharedPreferencesProvider).setBool(_key, v);
  }
}

/// The colours the chapter page is read in. [auto] follows the app's theme; the
/// others set the page and text colours for the reader alone.
///
/// Each pairing keeps body text, secondary text and the green accent at 4.5:1
/// or better against its own page, so verse numbers stay readable on all of
/// them (the tests check this).
enum ReaderTheme {
  auto(null, null, null, null, null, null, false),
  light(Color(0xFFFFFFFF), Color(0xFF1D2327), Color(0xFF5B666E),
      Color(0xFF2E7D32), Color(0xFFEEF1F2), Color(0xFFF5F7F8), false),
  sepia(Color(0xFFF4ECD8), Color(0xFF3B2F23), Color(0xFF6B5B49),
      Color(0xFF2F6F37), Color(0xFFE8DDC0), Color(0xFFFBF6E9), false),
  slate(Color(0xFF1E2A35), Color(0xFFE3E8EC), Color(0xFFA9B4BD),
      Color(0xFF7BD08A), Color(0xFF2C3B49), Color(0xFF263544), true),
  night(Color(0xFF000000), Color(0xFFD6D6D6), Color(0xFF9A9A9A),
      Color(0xFF6FCF7D), Color(0xFF1C1C1C), Color(0xFF141414), true);

  const ReaderTheme(this.background, this.text, this.muted, this.accent,
      this.chip, this.raised, this.isDark);

  /// Page colour; null for [auto].
  final Color? background;
  final Color? text;

  /// Secondary text: version label, selection count.
  final Color? muted;

  /// Verse numbers, links and selection.
  final Color? accent;

  /// Pill and field grounds.
  final Color? chip;

  /// Sheets and the selection panel, a step off the page.
  final Color? raised;
  final bool isDark;

  /// [parent] recoloured for this theme (unchanged for [auto]).
  ///
  /// Starts from the app's own light or dark theme, so every other surface
  /// (fields, dividers, errors) matches the brightness of the page.
  ThemeData apply(ThemeData parent) {
    if (this == auto) return parent;
    final base = isDark ? AppTheme.dark() : AppTheme.light();
    return base.copyWith(
      scaffoldBackgroundColor: background,
      colorScheme: base.colorScheme.copyWith(
        surface: background,
        onSurface: text,
        onSurfaceVariant: muted,
        primary: accent,
        onPrimary: isDark ? const Color(0xFF000000) : const Color(0xFFFFFFFF),
        secondaryContainer: chip,
        onSecondaryContainer: text,
        surfaceContainerHighest: chip,
        surfaceContainerHigh: raised,
        surfaceContainer: raised,
      ),
    );
  }
}

final readerThemeProvider =
    NotifierProvider<ReaderThemeNotifier, ReaderTheme>(ReaderThemeNotifier.new);

class ReaderThemeNotifier extends Notifier<ReaderTheme> {
  static const _key = 'bible_reader_theme';

  @override
  ReaderTheme build() => _read(ref.read(sharedPreferencesProvider), _key,
      ReaderTheme.values, ReaderTheme.auto);

  Future<void> set(ReaderTheme v) async {
    if (v == state) return;
    state = v;
    await ref.read(sharedPreferencesProvider).setString(_key, v.name);
  }
}
