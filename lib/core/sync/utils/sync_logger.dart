import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

/// Simple logger for sync operations.
///
/// Every level goes to `dart:developer`, which surfaces in DevTools and the
/// VM service but not in the device's own log. The plain-stdout mirror is
/// debug-only on purpose: `print()` is never stripped from a release build, so
/// mirroring there put sync detail — user ids, operation ids, entity payload
/// shapes — into logcat and the iOS device console, readable by anything on
/// the device that can read system logs.
class SyncLogger {
  static const _name = 'Sync';

  /// Mirror to stdout so a developer watching `flutter run` sees sync activity
  /// without attaching DevTools. Dropped in release builds only.
  ///
  /// Gated on [kReleaseMode] rather than `!kDebugMode` to match the debugPrint
  /// mute in main.dart. Profile is the build you attach to a device to measure
  /// a real sync, and `!kDebugMode` silenced it there while leaving every
  /// other debugPrint in the app still writing to the device log — the
  /// opposite of the split this is for.
  static void _echo(String line) {
    if (kReleaseMode) return;
    // ignore: avoid_print
    print(line);
  }

  /// Log debug message
  static void debug(String message) {
    developer.log(message, name: _name, level: 500);
  }

  /// Log info message
  static void info(String message) {
    _echo('[Sync] $message');
    developer.log(message, name: _name, level: 800);
  }

  /// Log warning message
  static void warning(String message) {
    _echo('[Sync] WARNING: $message');
    developer.log(message, name: _name, level: 900);
  }

  /// Log error message
  static void error(String message, [Object? error, StackTrace? stackTrace]) {
    _echo('[Sync] ERROR: $message | $error');
    developer.log(
      message,
      name: _name,
      level: 1000,
      error: error,
      stackTrace: stackTrace,
    );
  }
}
