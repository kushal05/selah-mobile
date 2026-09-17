/// Which way a stalled change was travelling when sync gave up on it.
enum StalledDirection {
  /// Something this device did that the server would not accept.
  outgoing,

  /// Something from the server that this device could not apply.
  incoming,
}

/// A change sync has stopped trying to move, presented for the user to see.
///
/// Both directions end up here deliberately. The engine's rule is that nothing
/// leaves the system without a record: an outbound operation the server keeps
/// rejecting is quarantined rather than dropped from the queue, and an inbound
/// operation this device cannot apply is dead-lettered rather than skipped
/// silently. Neither is a crash, and neither is visible anywhere else — so
/// without this the user's own words about "it didn't sync" would have nothing
/// behind them.
class StalledChange {
  final StalledDirection direction;

  /// Entity this change was about, e.g. `note` / `abc-123`.
  final String entityType;
  final String entityId;

  /// Why sync stopped trying.
  final String reason;

  /// How many times it was attempted before being set aside.
  final int attempts;

  /// When it was last attempted, ms since epoch.
  final int lastAttemptAt;

  const StalledChange({
    required this.direction,
    required this.entityType,
    required this.entityId,
    required this.reason,
    required this.attempts,
    required this.lastAttemptAt,
  });
}
