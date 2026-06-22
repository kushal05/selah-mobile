import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/push_token_service.dart';
import '../../services/fcm_service.dart';
import 'sync_providers.dart';

// ── Service provider ──────────────────────────────────────────────────────────

final pushTokenServiceProvider = Provider<PushTokenService>((ref) {
  final config = ref.watch(syncConfigProvider);
  final interceptor = ref.watch(apiInterceptorProvider);
  return PushTokenService(config: config, interceptor: interceptor);
});

// ── Token registration provider ───────────────────────────────────────────────

/// Watches [currentUserIdProvider] and [deviceIdProvider]; registers (or
/// re-registers) the FCM token with the backend whenever the user ID changes
/// (i.e. after login) and whenever Firebase refreshes the token.
///
/// Activate once in the app by doing `ref.watch(fcmTokenRegistrationProvider)`.
final fcmTokenRegistrationProvider = Provider<void>((ref) {
  final userId = ref.watch(currentUserIdProvider);
  final deviceId = ref.watch(deviceIdProvider);

  // Skip registration for unauthenticated / placeholder state.
  if (userId == 'default-user-id' || deviceId == 'default-device-id') return;

  final service = ref.read(pushTokenServiceProvider);

  Future<void> registerToken(String token) async {
    try {
      await service.register(deviceId: deviceId, token: token);
      debugPrint('FCM token registered for device $deviceId');
    } catch (e) {
      debugPrint('FCM token registration failed: $e');
    }
  }

  // Register the current token.
  FcmService.instance.getToken().then((token) {
    if (token != null) registerToken(token);
  });

  // Re-register on token refresh.
  final sub = FcmService.instance.onTokenRefresh.listen(registerToken);
  ref.onDispose(sub.cancel);
});
