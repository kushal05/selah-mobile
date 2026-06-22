import 'dart:convert';

import '../../../../core/sync/config/sync_config.dart';
import '../../../../core/sync/services/api_interceptor.dart';
import '../../../../core/sync/services/auth_service.dart';
import '../../../../core/sync/services/sync_api_client.dart';
import '../models/device_model.dart';

/// Create a [SyncApiException] from an HTTP response, extracting
/// error details from the JSON body when available.
SyncApiException _exceptionFromResponse(dynamic response) {
  try {
    final body = jsonDecode(response.body as String) as Map<String, dynamic>;
    return SyncApiException(
      code: body['error'] as String? ?? 'UNKNOWN_ERROR',
      message: body['message'] as String? ?? 'Unknown error',
      statusCode: response.statusCode as int,
    );
  } catch (_) {
    return SyncApiException(
      code: 'HTTP_ERROR',
      message: 'HTTP ${response.statusCode}: ${response.reasonPhrase}',
      statusCode: response.statusCode as int,
    );
  }
}

/// Service for managing devices via the auth API.
///
/// Uses [ApiInterceptor] for automatic token refresh, retry, and timeouts.
class DeviceApiService {
  final SyncConfig config;
  final AuthService authService;
  final ApiInterceptor interceptor;
  final String deviceId;

  DeviceApiService({
    required this.config,
    required this.authService,
    required this.interceptor,
    required this.deviceId,
  });

  String get _baseUrl => '${config.apiBaseUrl}/v1/auth/devices';

  Map<String, String> get _headers => interceptor.headers(deviceId: deviceId);

  /// Fetch all devices for the current user.
  Future<List<DeviceModel>> getDevices() async {
    await interceptor.ensureValidToken();

    final response = await interceptor.get(
      Uri.parse(_baseUrl),
      headers: _headers,
    );

    if (response.statusCode != 200) {
      throw _exceptionFromResponse(response);
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final list = (body['devices'] as List? ?? []).cast<Map<String, dynamic>>();
    return list.map(DeviceModel.fromJson).toList();
  }

  /// Remove a specific device (revoke session).
  Future<void> removeDevice(String targetDeviceId) async {
    await interceptor.ensureValidToken();

    final response = await interceptor.delete(
      Uri.parse('$_baseUrl/$targetDeviceId'),
      headers: _headers,
    );

    if (response.statusCode != 200) {
      throw _exceptionFromResponse(response);
    }
  }

  /// Revoke all other devices except the current one.
  Future<int> revokeOtherDevices(String currentDeviceId) async {
    await interceptor.ensureValidToken();

    final response = await interceptor.post(
      Uri.parse('$_baseUrl/revoke-others'),
      headers: _headers,
      body: jsonEncode({'currentDeviceId': currentDeviceId}),
    );

    if (response.statusCode != 200) {
      throw _exceptionFromResponse(response);
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return body['revokedCount'] as int? ?? 0;
  }
}
