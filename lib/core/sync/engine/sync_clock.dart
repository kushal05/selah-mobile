import '../../testing/test_clock.dart';

/// The device clock, offset by what the server last said the time was.
///
/// Merges are decided by comparing timestamps that each device stamped from
/// its own clock, so "now" has to mean the same thing on every device or the
/// comparison is meaningless. This is the one reading of a clock that all
/// devices share.
///
/// **Where the offset comes from.** Only push responses. The server stamps
/// each accepted operation as it applies it, so that value is server time at
/// the moment of the request, give or take one network hop — small enough to
/// ignore against the skew threshold this exists to police.
///
/// A *pulled* operation also carries a `serverTimestamp`, and it is deliberately
/// not used here: it records when the server received that operation, which may
/// have been days ago, so reading it as "server now" would invent an enormous
/// negative offset.
///
/// **Not persisted, on purpose.** The offset would need a column on
/// `sync_state` and therefore a migration, to cover only the interval between
/// launch and the first push of the session. Before that first push [now]
/// returns the device clock, which is what every merge used before this class
/// existed — so the gap is the old behaviour, not a new failure.
///
/// **Not used for anything the user sees.** Dates on notes, habit streaks and
/// reminder times all stay on the device clock, via [TestClock]. A user whose
/// clock is wrong should see their own wrong clock consistently rather than
/// have "today" in the app disagree with "today" on their phone.
class SyncClock {
  SyncClock._();

  static int? _offsetMs;

  /// Server time minus device time as of the last push, or null if this
  /// process has not completed one.
  static int? get offsetMs => _offsetMs;

  /// Records that the server's clock read [serverMs] just now.
  static void observeServerTime(int serverMs) {
    _offsetMs = serverMs - TestClock.now();
  }

  /// The current time, corrected towards the server's clock where known.
  static int now() => TestClock.now() + (_offsetMs ?? 0);

  /// Drops the learnt offset. For tests, and for sign-out, where the next
  /// session may talk to a different server.
  static void reset() => _offsetMs = null;
}
