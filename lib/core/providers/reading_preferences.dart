import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../sync/providers/sync_providers.dart';

/// Reader text size, applied to long-form content: Bible chapters, note bodies
/// and song lyrics.
///
/// This is deliberately separate from the OS text-scale setting. Both apply —
/// the OS scale sizes the whole interface, this sizes the passage the user is
/// actually reading. Someone who wants larger scripture without enlarging every
/// label in the app can get it here, and a reader who has already turned the
/// system scale up still gets a usable multiple of it.
enum ReadingTextSize {
  small('Small', 0.875),
  standard('Standard', 1.0),
  large('Large', 1.25),
  larger('Larger', 1.5),
  largest('Largest', 1.875);

  const ReadingTextSize(this.label, this.scale);

  /// Human-facing name for the settings control.
  final String label;

  /// Multiplier applied to a base reading font size.
  final double scale;

  /// The next step up, or `this` if already at the maximum.
  ReadingTextSize get next =>
      this == largest ? this : ReadingTextSize.values[index + 1];

  /// The next step down, or `this` if already at the minimum.
  ReadingTextSize get previous =>
      this == small ? this : ReadingTextSize.values[index - 1];

  bool get isSmallest => this == small;
  bool get isLargest => this == largest;
}

/// Base size for body text in a reading surface, before [ReadingTextSize] is
/// applied. Verses were previously hardcoded at 15px; 17 matches the iOS body
/// default and is the floor this scale multiplies from.
const double kReadingBaseFontSize = 17;

/// Base size for the verse-number gutter, before scaling.
const double kVerseNumberBaseFontSize = 13;

/// Current reader text size. Persists across launches.
final readingTextSizeProvider =
    NotifierProvider<ReadingTextSizeNotifier, ReadingTextSize>(
  ReadingTextSizeNotifier.new,
);

class ReadingTextSizeNotifier extends Notifier<ReadingTextSize> {
  static const _prefsKey = 'reading_text_size';

  SharedPreferences get _prefs => ref.read(sharedPreferencesProvider);

  @override
  ReadingTextSize build() {
    final stored = _prefs.getString(_prefsKey);
    if (stored == null) return ReadingTextSize.standard;
    // A value written by a newer build, or a renamed enum, must not brick the
    // reader — fall back rather than throw.
    return ReadingTextSize.values
            .where((s) => s.name == stored)
            .firstOrNull ??
        ReadingTextSize.standard;
  }

  Future<void> set(ReadingTextSize size) async {
    if (size == state) return;
    state = size;
    await _prefs.setString(_prefsKey, size.name);
  }

  Future<void> increase() => set(state.next);

  Future<void> decrease() => set(state.previous);
}

/// The resolved body font size for reading surfaces.
final readingFontSizeProvider = Provider<double>((ref) {
  return kReadingBaseFontSize * ref.watch(readingTextSizeProvider).scale;
});

/// The resolved verse-number font size, scaled alongside the body.
final verseNumberFontSizeProvider = Provider<double>((ref) {
  return kVerseNumberBaseFontSize * ref.watch(readingTextSizeProvider).scale;
});
