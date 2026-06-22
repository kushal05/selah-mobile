import 'dart:convert';

import '../../../../core/sync/config/sync_config.dart';
import '../../../../core/sync/services/api_interceptor.dart';
import '../../domain/models/notification_preference.dart';

/// API service for reading and writing notification preferences.
class NotificationPrefApiService {
  final SyncConfig config;
  final ApiInterceptor interceptor;
  final String deviceId;

  NotificationPrefApiService({
    required this.config,
    required this.interceptor,
    required this.deviceId,
  });

  String get _baseUrl => '${config.apiBaseUrl}/v1/notifications';

  Map<String, String> get _headers => interceptor.headers(deviceId: deviceId);

  Future<List<NotificationPreference>> getPreferences() async {
    await interceptor.ensureValidToken();
    final response = await interceptor.get(
      Uri.parse('$_baseUrl/preferences'),
      headers: _headers,
    );
    if (response.statusCode != 200) {
      throw Exception(
          'NotificationPrefApiService.getPreferences failed: HTTP ${response.statusCode}');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final list =
        (body['preferences'] as List? ?? []).cast<Map<String, dynamic>>();
    return list.map(NotificationPreference.fromJson).toList();
  }

  Future<void> updatePreferences(
      List<NotificationPreference> preferences) async {
    await interceptor.ensureValidToken();
    final response = await interceptor.put(
      Uri.parse('$_baseUrl/preferences'),
      headers: _headers,
      body: jsonEncode({
        'preferences': preferences.map((p) => p.toJson()).toList(),
      }),
    );
    if (response.statusCode != 200) {
      throw Exception(
          'NotificationPrefApiService.updatePreferences failed: HTTP ${response.statusCode}');
    }
  }
}
