/// Injectable clock for deterministic testing.
///
/// In production, [TestClock.now()] returns [DateTime.now().millisecondsSinceEpoch].
/// In tests, call [TestClock.setFixed] to freeze time or [TestClock.advance] to
/// move it forward by a known delta.
///
/// Usage:
///   Replace every `DateTime.now().millisecondsSinceEpoch` with `TestClock.now()`.
///
/// IMPORTANT: This class is intentionally kept in `lib/` (not `test/`) because
/// production code (OplogEntry, model factories) must call it.
/// The overhead in release builds is a single static function call.
class TestClock {
  static int? _fixedNow;

  /// Returns the current timestamp in milliseconds since epoch.
  ///
  /// If a fixed timestamp has been set via [setFixed], returns that value.
  /// Otherwise, delegates to [DateTime.now()].
  static int now() {
    return _fixedNow ?? DateTime.now().millisecondsSinceEpoch;
  }

  /// Freeze the clock at [timestampMs] (milliseconds since epoch).
  static void setFixed(int timestampMs) {
    _fixedNow = timestampMs;
  }

  /// Advance the frozen clock by [delta] milliseconds.
  ///
  /// If the clock is not frozen, freezes it at `DateTime.now() + delta`.
  static void advance(int deltaMs) {
    _fixedNow = (_fixedNow ?? DateTime.now().millisecondsSinceEpoch) + deltaMs;
  }

  /// Reset to real-time mode.
  static void reset() {
    _fixedNow = null;
  }

  /// Whether the clock is currently frozen.
  static bool get isFrozen => _fixedNow != null;
}
