/// Central configuration for all integration tests.
class TestConfig {
  /// User ID used across all test scenarios.
  static const testUserId = 'test-user-00000000';

  /// Device ID used across all test scenarios.
  static const testDeviceId = 'test-device-00000000';

  /// Base timestamp for deterministic tests (2025-01-01 00:00:00 UTC).
  static const baseTimestamp = 1735689600000;

  /// Default timeout for async polling waits.
  static const defaultTimeout = Duration(seconds: 10);

  /// Polling interval for condition waiters.
  static const pollInterval = Duration(milliseconds: 100);

  /// Bounded pump duration (replaces pumpAndSettle).
  static const settleDuration = Duration(seconds: 2);
}
