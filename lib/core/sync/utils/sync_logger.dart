import 'dart:developer' as developer;

/// Simple logger for sync operations
///
/// Uses dart:developer log for debug builds and print() for release builds.
class SyncLogger {
  static const _name = 'Sync';

  /// Log debug message
  static void debug(String message) {
    developer.log(message, name: _name, level: 500);
  }

  /// Log info message
  static void info(String message) {
    // ignore: avoid_print
    print('[Sync] $message');
    developer.log(message, name: _name, level: 800);
  }

  /// Log warning message
  static void warning(String message) {
    // ignore: avoid_print
    print('[Sync] WARNING: $message');
    developer.log(message, name: _name, level: 900);
  }

  /// Log error message
  static void error(String message, [Object? error, StackTrace? stackTrace]) {
    // ignore: avoid_print
    print('[Sync] ERROR: $message | $error');
    developer.log(
      message,
      name: _name,
      level: 1000,
      error: error,
      stackTrace: stackTrace,
    );
  }
}
