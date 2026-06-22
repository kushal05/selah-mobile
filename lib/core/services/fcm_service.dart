import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../../firebase_options.dart';

/// Top-level handler for background FCM messages (must be a top-level function).
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Firebase must be initialized before using it in the background isolate.
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  debugPrint('FCM background message: ${message.messageId}');
}

/// Wraps FirebaseMessaging for permission requests, token management, and
/// foreground message handling.
class FcmService {
  FcmService._();

  static final FcmService instance = FcmService._();

  /// Initialize Firebase and register the background handler.
  /// Must be called before [runApp], after [WidgetsFlutterBinding.ensureInitialized].
  static Future<void> initialize() async {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  }

  /// Request notification permission (iOS + Android 13+).
  /// Returns true if permission was granted.
  Future<bool> requestPermission() async {
    final settings = await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    return settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
  }

  /// Returns the current FCM registration token, or null if not available.
  Future<String?> getToken() async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (kDebugMode) {
        debugPrint('╔══════════════════════════════════════════════════╗');
        debugPrint('║  FCM TOKEN (debug only)                          ║');
        debugPrint('╠══════════════════════════════════════════════════╣');
        debugPrint('║  $token');
        debugPrint('╚══════════════════════════════════════════════════╝');
      }
      return token;
    } catch (e) {
      debugPrint('FcmService.getToken failed: $e');
      return null;
    }
  }

  /// Stream that emits a new token whenever the FCM token is refreshed.
  Stream<String> get onTokenRefresh => FirebaseMessaging.instance.onTokenRefresh;

  /// Stream of FCM messages received while the app is in the foreground.
  Stream<RemoteMessage> get onMessage => FirebaseMessaging.onMessage;

  /// Stream of messages that caused the app to open from the background.
  Stream<RemoteMessage> get onMessageOpenedApp =>
      FirebaseMessaging.onMessageOpenedApp;

  /// Returns the message that launched the app from a terminated state, if any.
  Future<RemoteMessage?> getInitialMessage() =>
      FirebaseMessaging.instance.getInitialMessage();
}
