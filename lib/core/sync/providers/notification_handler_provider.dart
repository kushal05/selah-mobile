import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../navigation/navigator_keys.dart';
import '../../services/fcm_service.dart';
import '../../sync/services/notification_router.dart';
import 'sync_providers.dart';

/// Handles FCM messages: shows foreground notifications and navigates on tap.
///
/// Activate via `ref.watch(notificationHandlerProvider)` in [appRouterProvider].
final notificationHandlerProvider = Provider<void>((ref) {
  final notifService = ref.watch(notificationServiceProvider);

  // ── Foreground messages ────────────────────────────────────────────────────
  final foregroundSub = FcmService.instance.onMessage.listen((message) async {
    try {
      await notifService.showFcmNotification(message);
    } catch (e) {
      debugPrint('FCM foreground show failed: $e');
    }
  });

  // ── Background → foreground taps ──────────────────────────────────────────
  final openedSub = FcmService.instance.onMessageOpenedApp.listen((message) {
    _navigate(message.data);
  });

  ref.onDispose(() {
    foregroundSub.cancel();
    openedSub.cancel();
  });
});

/// Handles the initial message when the app is launched from a terminated state.
///
/// Call this once from a post-frame callback after the router is ready.
Future<void> handleInitialFcmMessage() async {
  final message = await FcmService.instance.getInitialMessage();
  if (message != null) {
    _navigate(message.data);
  }
}

void _navigate(Map<String, dynamic> data) {
  final path = NotificationRouter.routeFrom(data);
  if (path == null) return;
  final ctx = rootNavigatorKey.currentContext;
  if (ctx == null || !ctx.mounted) return;
  ctx.push(path);
}
