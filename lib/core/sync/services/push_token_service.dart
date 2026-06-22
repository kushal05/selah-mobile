import 'dart:convert';
import 'dart:io';

import '../config/sync_config.dart';
import '../services/api_interceptor.dart';

/// Registers and deregisters FCM push tokens with the backend.
class PushTokenService {
  final SyncConfig config;
  final ApiInterceptor interceptor;

  PushTokenService({required this.config, required this.interceptor});

  String get _platform => Platform.isIOS ? 'ios' : 'android';

  /// Register (upsert) a push token for the given device.
  Future<void> register({
    required String deviceId,
    required String token,
  }) async {
    await interceptor.ensureValidToken();
    final response = await interceptor.put(
      Uri.parse('${config.apiBaseUrl}/v1/auth/devices/$deviceId/push-token'),
      headers: interceptor.headers(deviceId: deviceId),
      body: jsonEncode({'token': token, 'platform': _platform}),
    );
    if (response.statusCode != 200) {
      throw Exception(
          'PushTokenService.register failed: HTTP ${response.statusCode}');
    }
  }
}
