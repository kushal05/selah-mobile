import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Turns an exception into something a person can act on.
///
/// The app previously rendered raw exceptions — `Error: $e` and
/// `Failed to move song to trash: $e` — in 130 places. To a non-technical
/// reader a stack-trace fragment does not say what happened, whether their
/// data is safe, or what to do next; it reads as "the app is broken and my
/// notes may be gone".
///
/// Every message here answers three questions: what happened, whether the
/// user's work is safe, and what to do now. The raw error is still logged via
/// [debugPrint] for diagnosis — it just never reaches the screen.
class UserFacingError {
  const UserFacingError._();

  /// A short, plain-language message for [error].
  ///
  /// [action] optionally names the thing being attempted, in lower case and
  /// as a verb phrase — 'save your note', 'delete this prayer'. It is woven
  /// into the message where one is available, so the text says which operation
  /// failed rather than that something, somewhere, went wrong.
  static String message(Object? error, {String? action}) {
    final what = action ?? 'complete that';
    _log(error, action);

    if (_isOffline(error)) {
      return "You're offline, so we couldn't $what right now. "
          'Your work is saved on this device and will sync automatically '
          'when you reconnect.';
    }
    if (_isTimeout(error)) {
      return "The connection is slow, so we couldn't $what. "
          'Nothing was lost — please try again.';
    }
    if (_isAuth(error)) {
      return 'Your session has expired. Please sign in again to continue.';
    }
    if (_isPermission(error)) {
      return "You don't have permission to $what. "
          'If this is shared with you, ask the owner for access.';
    }
    if (_isNotFound(error)) {
      return "We couldn't find that item — it may have been deleted or moved. "
          'Check Settings → Trash if you think it should still be here.';
    }
    if (_isStorage(error)) {
      return "There isn't enough space on this device to $what. "
          'Free up some space and try again.';
    }
    if (_isConflict(error)) {
      return 'This was changed on another device. '
          'Reopen it to see the latest version, then try again.';
    }
    return "Something went wrong and we couldn't $what. "
        'Your existing data is safe. Please try again in a moment.';
  }

  /// Convenience for the very common `AsyncValue.error` builder, where no
  /// specific action is in scope.
  static String forLoad(Object? error, {String? what}) {
    _log(error, what == null ? 'load' : 'load $what');
    if (_isOffline(error)) {
      return "You're offline. Showing what's saved on this device — "
          'reconnect to see the latest.';
    }
    if (_isTimeout(error)) {
      return 'That took too long to load. Please try again.';
    }
    if (_isAuth(error)) {
      return 'Your session has expired. Please sign in again to continue.';
    }
    return what == null
        ? "We couldn't load this. Please try again."
        : "We couldn't load your $what. Please try again.";
  }

  static void _log(Object? error, String? action) {
    if (error == null) return;
    debugPrint('[UserFacingError]${action == null ? '' : ' ($action)'} $error');
  }

  // ── Classification ──────────────────────────────────────────────────────
  // Matching is done on type first and message text second. Message matching
  // is a heuristic — it is only ever used to pick friendlier wording, and the
  // generic fallback is already safe, so a miss degrades gracefully.

  static bool _isOffline(Object? e) =>
      e is SocketException ||
      _matches(e, ['socketexception', 'failed host lookup', 'network is unreachable',
        'no address associated', 'connection refused', 'connection closed',
        'clientexception', 'no internet']);

  static bool _isTimeout(Object? e) =>
      e is TimeoutException || _matches(e, ['timeout', 'timed out', 'deadline exceeded']);

  static bool _isAuth(Object? e) =>
      _matches(e, ['401', 'unauthori', 'token expired', 'invalid token',
        'authentication failed', 'not signed in']);

  static bool _isPermission(Object? e) =>
      _matches(e, ['403', 'forbidden', 'permission denied', 'not allowed', 'access denied']);

  static bool _isNotFound(Object? e) =>
      _matches(e, ['404', 'not found', 'does not exist', 'no such']);

  static bool _isStorage(Object? e) =>
      e is FileSystemException ||
      _matches(e, ['no space', 'disk full', 'quota exceeded', 'database or disk is full']);

  static bool _isConflict(Object? e) =>
      _matches(e, ['409', 'conflict', 'version mismatch', 'stale']);

  static bool _matches(Object? e, List<String> needles) {
    if (e == null) return false;
    final text = e.toString().toLowerCase();
    return needles.any(text.contains);
  }
}
